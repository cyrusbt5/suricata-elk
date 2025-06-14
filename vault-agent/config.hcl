exit_after_auth = false
pid_file = "/tmp/pidfile"

auto_auth {
  method "approle" {
    mount_path = "auth/approle"
    config = {
      role_id_file_path = "/vault-creds/role_id"
      secret_id_file_path = "/vault-creds/secret_id"
    }
  }

  sink "file" {
    config = {
      path = "/vault/.vault-token"
    }
  }
}

vault {
  address = "http://vault:8200"
}

template {
  source      = "/etc/vault/templates/.env.ctmpl"
  destination = "/secrets/.env"
  perms       = "0644"
}

template {
  source      = "/etc/vault/templates/filebeat.yml.ctmpl"
  destination = "/secrets/filebeat.yml"
  perms       = "0644"
}
