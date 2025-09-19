#!/bin/bash -e

NETWORK_NAME=${1:-"testnet"}
RESTORE_PATH=${2:-"$HOME/.movement"}

export AWS_REGION="us-west-2"
export RESTIC_PASSWORD="movebackup"
export RESTIC_HOST="${NETWORK_NAME}_fullnode"
export SYNC_BUCKET="movement-sync-${NETWORK_NAME}"
export RESTIC_REPOSITORY="s3:s3.${AWS_REGION}.amazonaws.com/${SYNC_BUCKET}/restic_node_backup"

# Remove old DB files
echo "Removing Maptos DB files"
if [ -d "$RESTORE_PATH/maptos" ]; then
  rm -rf "$RESTORE_PATH/maptos"
fi
if [ -d "$DOT_MOVEMENT_PATH/maptos-storage" ]; then
  rm -rf "$RESTORE_PATH/maptos-storage"
fi
if [ -d "$RESTORE_PATH/movement-da-db" ]; then
  rm -rf "$RESTORE_PATH/movement-da-db"
fi

echo "Restoring latest snapshot from Restic..."

restic \
  --no-lock \
  -r "s3:s3.${AWS_REGION}.amazonaws.com/${SYNC_BUCKET}/restic_node_backup" \
  --host "$RESTIC_HOST" \
  restore latest \
  --target "$RESTORE_PATH" \
  --include "/.movement/maptos" \
  --include "/.movement/maptos-storage" \
  --include "/.movement/movement-da-db" \
  --include "/.movement/default_signer_address_whitelist" \
  -o s3.unsafe-anonymous-auth=true

echo "Restore complete."