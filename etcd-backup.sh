#!/bin/bash -e

export ETCDCTL_API=3

dateStamp=$(date +%Y%m%d)
dest_folder="."
host=$(hostname -s)
dest_file_name="etcd-snapshot_${host}_${dateStamp}"
dest_file="$dest_folder/${dest_file_name}.db"
# slack channel webhook
WEBHOOK_URL="$WEBHOOK_URL"
S3_BUCKET="${S3_BUCKET:-etcd-backup}"

if [ -z "$cacert_file" ] || ! [ -f "$cacert_file" ]; then
  echo "CA cert file is mandatory, please set it in ENV."
  exit 1
fi
if [ -z "$cert_file" ] || ! [ -f "$cert_file" ]; then
  echo "Cert file is mandatory, please set it in ENV."
  exit 1
fi
if [ -z "$key_file" ] || ! [ -f "$key_file" ]; then
  echo "Key file is mandatory, please set it in ENV."
  exit 1
fi
if [ -z "$etcd_endpoints" ]; then
  echo "ETCD Endpoints are mandatory, please set it in ENV."
  exit 1
fi

# send notification to slack channel
function slack_alert() {
  data=""
  printf -v data '{"text": "%s"}' "$@"
  if [ -n "$WEBHOOK_URL" ]; then
    curl -X POST -H 'Content-type: application/json' --data "$data" "$WEBHOOK_URL"
  fi
}

function check_result() {
  if [[ -n "$1" && "$1" -ne 0 ]]; then
    if [ -n "$DEBUG" ]; then
      echo "Proccess failed with code $1"
      echo "Sending slack alert: ${ENV_NAME:-Unknown}: ETCD backup: FAIL"
    else
      echo "Proccess failed with code $1"
      # send slack notification
      slack_alert "${ENV_NAME:-Unknown}: ETCD backup: FAIL"
      exit "$1"
    fi
  fi
}

function slack_ok() {
  if [ -n "$DEBUG" ]; then
    echo "Sending slack alert: ${ENV_NAME:-Unknown}: ETCD backup: OK"
  else
    slack_alert "${ENV_NAME:-Unknown}: ETCD backup: OK"
  fi
}

function get_snapshot() {
  echo "Generating snapshot file '$dest_file' ..."
  etcdctl snapshot save "$dest_file" --cacert="$cacert_file" --cert="$cert_file" --key="$key_file" --endpoints="$etcd_endpoints"
  local result=$?
  echo "Snapshot done with code $result."
  check_result $result
  file "$dest_file"
  echo "Generating snapshot md5sum ..."
  md5sum "$dest_file" > "${dest_file}.md5sum"
  check_result $?
}

function load_snapshot() {
  echo "Run following command to load snapshot file '$dest_file' ..."
  # TODO verify etcd restore
  echo "ETCDCTL_API=3 etcdctl snapshot restore \"$dest_file\" --cacert=\"$cacert_file\" --cert=\"$cert_file\" --key=\"$key_file\" --endpoints=\"$etcd_endpoints\""
}

function verify_snapshot() {
  echo "Verifying snapshot file '$dest_file' ..."
  if ! [ -f "$dest_file" ]; then
    echo "$dest_file not exists!"
    check_result 1
  fi
  if [ -f "${dest_file}.md5sum" ]; then
    echo "Verifying md5sum of file ..."
    md5sum -c "${dest_file}.md5sum"
    check_result $?
  else
    echo "Missing md5sum file, skipping md5sum check"
  fi
  etcdutl --write-out=table snapshot status "$dest_file"
  check_result $?
}

function encrypt_snapshot() {
  echo "Encrypting snapshot file '$dest_file' ..."

  # generate the publickey, using etcd private key
  echo "Generating publickey ..."
  openssl rsa -in "$key_file" -out "${dest_file}.publickey" -outform PEM -pubout
  check_result $?

  echo "Generating random password ..."
  openssl rand -hex -out "${dest_file}.password" 64
  check_result $?

  echo "Generating password md5sum ..."
  md5sum "${dest_file}.password" > "${dest_file}.password.md5sum"
  check_result $?

  # encrypt the file, using aes-256-cbc and protect with previously generated random password
  echo "Encrypting the file ..."
  openssl enc -pbkdf2 -in "$dest_file" -aes-256-cbc -pass "file:${dest_file}.password" -out "${dest_file}.aes256"
  check_result $?

  # encrypt the password file, using previously generated publickey
  echo "Encrypting password file ..."
  openssl pkeyutl -encrypt -inkey "${dest_file}.publickey" -pubin -in "${dest_file}.password" -out "${dest_file}.password.encrypted"
  remove_file "${dest_file}"
  remove_file "${dest_file}.password"
  remove_file "${dest_file}.publickey"
}

function decrypt_snapshot() {
  echo "Decrypting snapshot file '${dest_file}.aes256' ..."

  if ! [ -f "${dest_file}.aes256" ]; then
    echo "Missing encrypted file!"
    check_result 1
  fi
  if ! [ -f "${dest_file}.password.encrypted" ]; then
    echo "Missing encrypted password file!"
    check_result 1
  fi
  if ! [ -f "${key_file}" ]; then
    echo "Missing private key file!"
    check_result 1
  fi

  # decrypt the password file, using etcd private key
  echo "Decrypting password file ..."
  openssl pkeyutl -decrypt -inkey "${key_file}" -in "${dest_file}.password.encrypted" -out "${dest_file}.password"
  check_result $?

  if [ -f "${dest_file}.password.md5sum" ]; then
    echo "Verifying password file md5sum ..."
    md5sum -c "${dest_file}.password.md5sum"
    check_result $?
  else
    echo "No md5sum found for password file, skipping md5sum check"
  fi

  # decrypt the snapshot file, using previously decrypted password
  echo "Decrypting snapshot file ..."
  openssl enc -d -pbkdf2 -aes-256-cbc -in "${dest_file}.aes256" -out "${dest_file}" -pass "file:${dest_file}.password"
  check_result $?
  if [ -f "${dest_file}.md5sum" ]; then
    echo "Verifying snapshot file md5sum ..."
    md5sum -c "${dest_file}.md5sum"
    check_result $?
  else
    echo "No md5sum file found for snapshot, skipping md5sum check"
  fi
}

function compress() {
  if ! [ -f "${dest_file}.aes256" ]; then
    echo "Missing encrypted snapshot file!"
    check_result 1
  fi
  if ! [ -f "${dest_file}.password.encrypted" ]; then
    echo "Missing encrypted password file!"
    check_result 1
  fi

  sleep 10
  echo "Archiving and compressing files ..."
  tar -cjf "${dest_file}.tbz" ${dest_file}.*
  check_result $?

  remove_file "${dest_file}.password.encrypted"
  remove_file "${dest_file}.aes256"

  if [ -f "${dest_file}.md5sum" ]; then
    remove_file "${dest_file}.md5sum"
  else
    echo "WARNING: No md5sum file found for snapshot!"
  fi

  if [ -f "${dest_file}.password.md5sum" ]; then
    remove_file "${dest_file}.password.md5sum"
  else
    echo "WARNING: No md5sum file found for password!"
  fi
}

function decompress() {
  if [[ "$dest_file" == *.tbz ]]; then
    echo "Removing tbz extension from destination file ..."
    dest_file=${dest_file%.tbz}
  fi
  tar -xjf "${dest_file}.tbz"
}

function put_on_s3() {
  local FILE_TO_UPLOAD="$1"
  local FILE_NAME=$(basename "$FILE_TO_UPLOAD")
  echo "Uploading $FILE_NAME on s3/${S3_BUCKET}"
  mc cp -q "$FILE_TO_UPLOAD" "s3/${S3_BUCKET}/etcd/${FILE_NAME}"
  local upload_status=$?
  check_result $upload_status
}

function remove_file() {
  local FILE_NAME="$1"
  echo "Removing $FILE_NAME ..."
  rm -f "$FILE_NAME"
}

function upload_to_s3() {
  if ! [ -f "${dest_file}.tbz" ]; then
    echo "Missing archived snapshot file!"
    check_result 1
  fi
  put_on_s3 "${dest_file}.tbz"
  remove_file "${dest_file}.tbz"
}

function download_from_s3() {
  local FILE_TO_DOWNLOAD="$1"
  echo "Downloading $FILE_TO_DOWNLOAD from s3/${S3_BUCKET}"
  mc cp -q "s3/${S3_BUCKET}/etcd/${FILE_TO_DOWNLOAD}" "${FILE_TO_DOWNLOAD}"
  local download_status=$?
  check_result $download_status
  echo
  ls -lh "${FILE_TO_DOWNLOAD}"
}

function list_s3_files() {
  echo "Listing ${S3_BUCKET} files"
  mc ls -q "s3/${S3_BUCKET}/etcd"
}

function check_s3_bucket() {
  echo "Checking S3 bucket $S3_BUCKET"
  mc stat -q "s3/${S3_BUCKET}"
  local bucket_status=$?
  check_result $bucket_status
}

function DefaultAction() {
  check_s3_bucket
  get_snapshot
  verify_snapshot
  encrypt_snapshot
  compress
  upload_to_s3
  slack_ok
}

function LoadAction() {
  decompress
  decrypt_snapshot
  verify_snapshot
  load_snapshot
}

function Help() {
  cat <<EOF
List avilable options:
snapshot - Create new snapshot
load - Decompress, decrypt, verify and load snapshot
upload - Upload snapshot to S3
download - Download snapshot from S3
list - List snapshots on S3
encrypt - Encrypt snapshot
decrypt - Decrypt snapshot
compress - Compress snapshot
decompress - Decompress snapshot
verify - Verify etcd snapshot
backup - Create, verify, encrypt, compress and upload snapshot to S3
EOF
}

if [ -n "$1" ]; then
  action=$1
  shift
  case "$action" in
    "snapshot")
      get_snapshot
  ;;
    "load")
      if [ -z "$1" ]; then
        echo "File is mandatory!"
        exit 1
      fi
      dest_file=$1
      LoadAction
  ;;
    "upload")
      if [ -z "$1" ]; then
        echo "File is mandatory!"
        exit 1
      fi
      dest_file=$1
      upload_to_s3
  ;;
    "download")
      if [ -z "$1" ]; then
        echo "File is mandatory!"
        exit 1
      fi
      download_from_s3 "$1"
  ;;
    "list")
      list_s3_files
  ;;
    "encrypt")
      if [ -z "$1" ]; then
        echo "File is mandatory!"
        exit 1
      fi
      dest_file=$1
      encrypt_snapshot
  ;;
    "decrypt")
      if [ -z "$1" ]; then
        echo "File is mandatory!"
        exit 1
      fi
      dest_file=$1
      decrypt_snapshot
  ;;
    "compress")
      if [ -z "$1" ]; then
        echo "File is mandatory!"
        exit 1
      fi
      dest_file=$1
      compress
  ;;
    "decompress")
      if [ -z "$1" ]; then
        echo "File is mandatory!"
        exit 1
      fi
      dest_file=$1
      decompress
  ;;
    "verify")
      if [ -z "$1" ]; then
        echo "File is mandatory!"
        exit 1
      fi
      dest_file=$1
      verify_snapshot
  ;;
    "backup")
      DefaultAction
  ;;
    *)
      echo "Action $action not defined!"
      Help
  ;;
  esac
else
  Help
fi
