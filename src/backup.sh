#! /bin/sh

set -eu
set -o pipefail

source ./env.sh

echo "Creating backup of $POSTGRES_DATABASE database..."
pg_dump --format=custom \
        -h $POSTGRES_HOST \
        -p $POSTGRES_PORT \
        -U $POSTGRES_USER \
        -d $POSTGRES_DATABASE \
        $PGDUMP_EXTRA_OPTS \
        > db.dump



backup_to_file()
{
  s3_uri_base=$1
  metadata=$2
  if [ -n "$PASSPHRASE" ]; then
    echo "Encrypting backup..."
    gpg --symmetric --batch --passphrase "$PASSPHRASE" db.dump
    rm db.dump
    local_file="db.dump.gpg"
    s3_uri="${s3_uri_base}.gpg"
  else
    local_file="db.dump"
    s3_uri="$s3_uri_base"
  fi

  echo "Uploading backup to $S3_BUCKET..."
  aws $aws_args s3 cp "$local_file" "$s3_uri" --metadata="${metadata}"

  echo "Backup complete."
}

timestamp=$(date +"%Y-%m-%dT%H:%M:%S")
backup_each_f="${S3_PREFIX}/${POSTGRES_DATABASE}_${timestamp}.dump"
backup_each="s3://${S3_BUCKET}/${backup_each_f}"

timestamp=$(date +"%Y-%m-%d")
backup_daily_f="${S3_PREFIX}/${POSTGRES_DATABASE}_${timestamp}.dump"
backup_daily="s3://${S3_BUCKET}/{$backup_daily_f}"

backup_to_file $backup_each "backup_type=each"
backup_to_file $backup_daily "backup_type=daily"

aws s3api put-object-tagging --bucket "s3://${S3_BUCKET}" --key "${backup_daily_f}" --tagging 'TagSet=[{Key=backup-type,Value=daily}]'
aws s3api put-object-tagging --bucket "s3://${S3_BUCKET}" --key "${backup_each_f}" --tagging 'TagSet=[{Key=backup-type,Value=each}]'
