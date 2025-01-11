#!/bin/bash -e

HOMEDIR="${HOMEDIR:-/opt/backup/data}"
VAULT_S3="${VAULT_S3:-/vault/secrets/s3}"

[ -f "$VAULT_S3" ] && source "$VAULT_S3"

if [[ -n "$ACCESS_KEY_ID" && -n "$ACCESS_SECRET_KEY" ]]; then
[ -d "${HOMEDIR}/.mc" ] || mkdir -m 700 "${HOMEDIR}/.mc"
cat <<EOF> "${HOMEDIR}/.mc/config.json"
{
  "version": "10",
  "aliases": {
    "s3": {
      "url": "${S3_ENDPOINT:-https://s3.amazonaws.com}",
      "accessKey": "$ACCESS_KEY_ID",
      "secretKey": "$ACCESS_SECRET_KEY",
      "api": "s3v4",
      "path": "dns"
    }
  }
}
EOF
else
  echo "ERROR: ACCESS_KEY_ID or ACCESS_SECRET_KEY is missing"
fi

exec "$@"
