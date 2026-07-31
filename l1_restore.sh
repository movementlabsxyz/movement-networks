#!/bin/bash -e
#
# Movement Network L1 (Aptos) Database Restore Script
#
# This script restores aptos-node data from Movement Labs' public restic backups.
# Use this to bootstrap an archival node with existing blockchain data.
#
# Usage:
#   ./l1_restore.sh [mainnet|testnet] [/path/to/restore]
#
# Prerequisites:
#   - restic installed (https://restic.net/)
#   - Sufficient disk space (mainnet ~700GB, testnet ~260GB)
#
# The backups are updated hourly and maintain 14 days of snapshots.

set -e

NETWORK="${1:-testnet}"
RESTORE_PATH="${2:-./data}"

echo "Movement Network L1 Database Restore"
echo "====================================="
echo "Network: $NETWORK"
echo "Restore path: $RESTORE_PATH"
echo ""

# Network-specific settings
case "$NETWORK" in
  mainnet)
    export RESTIC_REPOSITORY="s3:https://s3.us-west-2.amazonaws.com/movement-pfn-backups-mainnet/movement-network-mainnet-fn-01"
    export RESTIC_PASSWORD="movebackup"
    echo "Using mainnet backup repository"
    echo "Expected data size: ~700GB"
    ;;
  testnet)
    export RESTIC_REPOSITORY="s3:https://s3.us-west-2.amazonaws.com/movement-sync-k8s-testnet/movement-network-testnet-pfn-backup"
    export RESTIC_PASSWORD="2kZpmsLW3OHM2I2B6210EnxjAEwbysT3Epbqvlyrmw"
    echo "Using testnet backup repository"
    echo "Expected data size: ~260GB"
    ;;
  *)
    echo "Error: Unknown network '$NETWORK'"
    echo "Usage: $0 [mainnet|testnet] [/path/to/restore]"
    exit 1
    ;;
esac

export AWS_DEFAULT_REGION="us-west-2"

# Create restore directory
mkdir -p "$RESTORE_PATH"

echo ""
echo "Listing available snapshots (most recent 5)..."
restic snapshots --latest 5 --no-lock -o s3.unsafe-anonymous-auth=true

echo ""
echo "Starting restore of latest snapshot..."
echo "This may take several hours depending on your network speed."
echo ""

# Resolve the latest snapshot ID explicitly before restoring.
# Using `restic restore latest --path <path>` would filter by backup source path,
# which breaks when the backup structure changes (e.g. db subdirs backed up
# separately instead of the parent /opt/data/aptos directory). Resolving the ID
# first ensures we always restore the most recent snapshot regardless of how the
# source paths are organised.
SNAPSHOT_ID=$(restic snapshots --latest 1 --no-lock -o s3.unsafe-anonymous-auth=true --json 2>/dev/null | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ -z "$SNAPSHOT_ID" ]; then
  echo "Error: Could not determine latest snapshot ID"
  exit 1
fi

echo "Restoring snapshot: $SNAPSHOT_ID"
echo ""

restic restore "$SNAPSHOT_ID" \
  --target "$RESTORE_PATH" \
  --no-lock \
  -o s3.unsafe-anonymous-auth=true

echo ""
echo "Restore complete!"
echo ""
echo "Data has been restored to: $RESTORE_PATH"
echo ""
echo "Next steps:"
echo "1. Move the restored data to your node's data directory:"
echo "   mv $RESTORE_PATH/opt/data/aptos/* /your/node/data/dir/"
echo ""
echo "2. Download genesis files for $NETWORK from:"
echo "   https://github.com/movement-network/movement-networks/tree/main/$NETWORK"
echo ""
echo "3. Use the appropriate fullnode.yaml or archival-fullnode.yaml config"
echo "   from the same directory."
echo ""
echo "4. Start your node!"
