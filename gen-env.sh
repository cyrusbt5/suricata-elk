#!/usr/bin/env bash
set -e

echo "VAULT_UID=$(id -u)" > .env
echo "VAULT_GID=$(id -g)" >> .env
echo "Generated .env with UID=$(id -u) and GID=$(id -g)"
