#!/usr/bin/env bash

set -e
set -o pipefail

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "[+] Docker is not installed. Please install Docker first." 1>&2
    exit 1
fi

# Check if Docker Compose is installed
if ! command -v docker compose &> /dev/null; then
    echo "[+] Docker Compose is not installed. Please install Docker Compose first." 1>&2
    exit 1
fi

# Bring up elasticsearch service
echo "[+] Starting Elasticsearch..."
docker compose up -d elasticsearch

echo "[+] Waiting for Elasticsearch to be green..."

until curl --silent --user elastic:changeme http://localhost:9200/_cluster/health | grep -q 'unable to authenticate user' ; do
    echo "[+] Elasticsearch is not ready yet. Waiting..."
    sleep 5
done

echo "[+] Elasticsearch is green. Setting up passwords..."
docker exec elasticsearch bin/elasticsearch-setup-passwords auto --batch > passwords.txt

echo "[+] Generating .env..."
./gen-env.sh

set -a
source .env
set +a

docker compose up -d vault-agent
docker run -t -d --name vault-admin --network suricata-elk_vault-net -e VAULT_ADDR='http://vault:8200' hashicorp/vault:1.19.5 cat

# Ensure vault-admin is removed on exit or interruption (Ctrl-C)
trap ' echo "[+] Cleaning up..." ; docker rm -f vault-admin 2>/dev/null || true' EXIT INT TERM

sleep 10

docker exec vault-admin vault login root
docker exec vault-admin vault status
docker exec vault-admin vault auth enable approle

# Assume you're already logged into Vault (via Vault Agent container)
VAULT_PATH=secret/elk 

while read -r line; do
  if [[ "$line" == PASSWORD* ]]; then
    user=$(echo "$line" | cut -d' ' -f2)
    pass=$(echo "$line" | cut -d'=' -f2 | tr -d ' ')
    echo "Storing $user in Vault..."
    docker exec vault-admin vault kv put "$VAULT_PATH/$user" password="$pass"
  fi
done < passwords.txt

echo '
path "secret/data/elk/*" {
  capabilities = ["read"]
}
' | docker exec -i vault-admin vault policy write elk-approle-policy -


docker exec vault-admin vault write auth/approle/role/elk-role token_policies="elk-approle-policy"
docker exec vault-admin vault read -field=role_id auth/approle/role/elk-role/role-id > vault-creds/role_id

docker exec vault-admin vault write -f -field=secret_id auth/approle/role/elk-role/secret-id > vault-creds/secret_id

docker compose up -d vault-agent

sleep 5

while [ ! -f ./secrets/filebeat.yml ]; do
  echo "[+] Waiting for Vault Agent to render template..."
  sleep 2
done

echo "[+] filebeat.yml rendered"


echo "[+] Starting Docker environment..."

docker compose --env-file ./secrets/.env up -d

echo "[✓] Environment bootstrapped."
