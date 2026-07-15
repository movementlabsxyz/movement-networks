#!/bin/bash -e
#
# Movement Network Database Restore (native, via aptos-debugger)
#
# Restores an Aptos archival DB from Movement Labs' public continuous-backup
# S3 bucket using only aptos-debugger and the AWS CLI. Produces a full chain
# from genesis (oldest_ledger_version = 0) — suitable for archival fullnodes.
#
# Usage:
#   ./database-restore.sh [mainnet|testnet] [/path/to/restore] [options]
#
# Options:
#   --force                 Remove any existing restore data before starting.
#   --downloader=<tool>     Metadata fetch strategy. One of:
#                             debugger (default) — aptos-debugger fetches each
#                               metadata file on demand via aws-cli. Slow on
#                               busy buckets but no extra dependency.
#                             s5cmd — bulk-download metadata in parallel before
#                               the restore. Requires s5cmd on PATH; much faster.
#
# Examples:
#   ./database-restore.sh testnet ./data
#   ./database-restore.sh mainnet ./data --force
#   ./database-restore.sh testnet ./data --downloader=s5cmd
#
# Prerequisites:
#   - aptos-debugger from the latest movementlabsxyz/aptos-core release:
#     https://github.com/movementlabsxyz/aptos-core/releases/latest
#   - aws CLI (https://aws.amazon.com/cli/)
#   - s5cmd (https://github.com/peak/s5cmd) — required only if you pass
#     --downloader=s5cmd
#   - Sufficient disk space:
#       mainnet  ~700 GB
#       testnet  ~260 GB
#
# Approximate wall-clock:
#   mainnet  ~3 h   (replay dominates; metadata phase is small either way)
#   testnet  ~2 h with --downloader=s5cmd, ~4 h with --downloader=debugger
#
# The IaC counterpart at
#   infra/tofu-network-nodes/modules/kubernetes-movement-node/scripts/entrypoint-native-restore.sh
# shares the same adapter shapes (debugger vs s5cmd); keep them in sync if you
# change either.

set -e

NETWORK="${1:-testnet}"
RESTORE_PATH="${2:-./data}"
FORCE=false
DOWNLOADER=debugger

for arg in "${@:3}"; do
  case "$arg" in
    --force) FORCE=true ;;
    --downloader=*) DOWNLOADER="${arg#*=}" ;;
    *) echo "Error: unknown option '$arg'" >&2; exit 1 ;;
  esac
done

case "$DOWNLOADER" in
  debugger|s5cmd) ;;
  *) echo "Error: --downloader must be 'debugger' or 's5cmd' (got '$DOWNLOADER')" >&2; exit 1 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Movement Network Database Restore (native)"
echo "==========================================="
echo "Network:      $NETWORK"
echo "Restore path: $RESTORE_PATH"
echo "Force:        $FORCE"
echo "Downloader:   $DOWNLOADER"
echo ""

# --- Network-specific defaults ---------------------------------------------
case "$NETWORK" in
  mainnet)
    S3_BUCKET="movement-m1-backup-mainnet"
    FALLBACK_TARGET_VERSION="142580846"
    ;;
  testnet)
    S3_BUCKET="movement-m1-backup-testnet"
    FALLBACK_TARGET_VERSION="103055419"
    ;;
  *)
    echo "Error: Unknown network '$NETWORK'" >&2
    echo "Usage: $0 [mainnet|testnet] [/path/to/restore] [--force]" >&2
    exit 1
    ;;
esac

S3_PREFIX="continuous-backup"
WAYPOINT_FILE="$SCRIPT_DIR/$NETWORK/waypoint.txt"

# --- Dependency check ------------------------------------------------------
for cmd in aptos-debugger aws; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: '$cmd' not found on PATH." >&2
    echo "  aptos-debugger: install the latest release from https://github.com/movementlabsxyz/aptos-core/releases/latest" >&2
    echo "  aws:            https://aws.amazon.com/cli/" >&2
    exit 1
  fi
done

if [ "$DOWNLOADER" = "s5cmd" ] && ! command -v s5cmd >/dev/null 2>&1; then
  echo "Error: --downloader=s5cmd was set but 's5cmd' is not on PATH." >&2
  echo "  Install it from https://github.com/peak/s5cmd or re-run without --downloader=s5cmd." >&2
  exit 1
fi

if [ ! -f "$WAYPOINT_FILE" ]; then
  echo "Error: waypoint file not found: $WAYPOINT_FILE" >&2
  echo "Run this script from a checkout of movementlabsxyz/movement-networks." >&2
  exit 1
fi

TRUST_WAYPOINT="$(tr -d '[:space:]' < "$WAYPOINT_FILE")"
echo "Trust waypoint (from $NETWORK/waypoint.txt): $TRUST_WAYPOINT"

# --- Auto-discover target_version from the latest state snapshot ----------
echo ""
echo "Discovering latest state snapshot in s3://$S3_BUCKET/$S3_PREFIX/ ..."
TARGET_VERSION="$(aws s3 ls "s3://$S3_BUCKET/$S3_PREFIX/" --no-sign-request 2>/dev/null \
  | grep -oE 'state_epoch_[0-9]+_ver_[0-9]+' \
  | sort -t_ -k4 -n \
  | tail -1 \
  | awk -F_ '{print $NF}' || true)"

if [ -z "$TARGET_VERSION" ]; then
  echo "Warning: could not auto-discover target_version; using fallback $FALLBACK_TARGET_VERSION" >&2
  TARGET_VERSION="$FALLBACK_TARGET_VERSION"
fi
echo "Target version: $TARGET_VERSION"

# --- Prepare restore directory --------------------------------------------
TARGET_DB_DIR="$RESTORE_PATH/aptos/db"
METADATA_CACHE_DIR="$RESTORE_PATH/.backup-restore-metadata"
LOCAL_METADATA_DIR="$RESTORE_PATH/.backup-metadata-local"
COMMAND_ADAPTER_CONFIG="$RESTORE_PATH/.restore-command-adapter.yaml"

if [ "$FORCE" = "true" ]; then
  echo "--force: removing existing $TARGET_DB_DIR, $METADATA_CACHE_DIR, $LOCAL_METADATA_DIR"
  rm -rf "$TARGET_DB_DIR" "$METADATA_CACHE_DIR" "$LOCAL_METADATA_DIR"
fi

mkdir -p "$TARGET_DB_DIR" "$METADATA_CACHE_DIR"

# --- If --downloader=s5cmd, pre-download metadata in parallel -------------
if [ "$DOWNLOADER" = "s5cmd" ]; then
  echo ""
  echo "Phase 1: parallel metadata pre-download via s5cmd"
  mkdir -p "$LOCAL_METADATA_DIR"
  s5cmd --no-sign-request --numworkers 64 sync \
    "s3://$S3_BUCKET/$S3_PREFIX/metadata/*" "$LOCAL_METADATA_DIR/"
  echo "Downloaded $(ls -1 "$LOCAL_METADATA_DIR" | wc -l) metadata files."
fi

# --- Write the command-adapter YAML ---------------------------------------
# Two shapes: hybrid (local-first + S3 fallback) when s5cmd pre-downloaded
# metadata, vs S3-only when it didn't. Keep both in sync with the IaC
# counterpart at
#   infra/tofu-network-nodes/modules/kubernetes-movement-node/scripts/entrypoint-native-restore.sh
if [ "$DOWNLOADER" = "s5cmd" ]; then
  cat > "$COMMAND_ADAPTER_CONFIG" <<'ADAPTER'
env_vars:
  - key: "BUCKET"
    value: "__BUCKET__"
  - key: "PREFIX"
    value: "__PREFIX__"
  - key: "LOCAL_METADATA"
    value: "__LOCAL_METADATA__"

commands:
  create_backup: 'echo "$PREFIX/$BACKUP_NAME"'
  create_for_write: 'echo "not supported for restore" >&2 && exit 1'
  open_for_read: 'HANDLE="$FILE_HANDLE"; if [ -f "$LOCAL_METADATA/$(basename $HANDLE)" ]; then cat "$LOCAL_METADATA/$(basename $HANDLE)"; else aws s3 cp "s3://$BUCKET/$PREFIX/$HANDLE" - --no-sign-request; fi'
  save_metadata_line: 'echo "not supported for restore" >&2 && exit 1'
  list_metadata_files: 'ls -1 $LOCAL_METADATA/ 2>/dev/null | sed "s|^|metadata/|" || true'
  backup_metadata_file: 'echo "not supported for restore" >&2 && exit 1'
ADAPTER
  sed -i "s|__BUCKET__|$S3_BUCKET|; s|__PREFIX__|$S3_PREFIX|; s|__LOCAL_METADATA__|$LOCAL_METADATA_DIR|" "$COMMAND_ADAPTER_CONFIG"
else
  cat > "$COMMAND_ADAPTER_CONFIG" <<'ADAPTER'
env_vars:
  - key: "BUCKET"
    value: "__BUCKET__"
  - key: "PREFIX"
    value: "__PREFIX__"

commands:
  create_backup: 'echo "$PREFIX/$BACKUP_NAME"'
  create_for_write: 'echo "not supported for restore" >&2 && exit 1'
  open_for_read: 'aws s3 cp "s3://$BUCKET/$PREFIX/$FILE_HANDLE" - --no-sign-request'
  save_metadata_line: 'echo "not supported for restore" >&2 && exit 1'
  list_metadata_files: 'aws s3 ls "s3://$BUCKET/$PREFIX/metadata/" --no-sign-request | awk "{print \"metadata/\"\$NF}"'
  backup_metadata_file: 'echo "not supported for restore" >&2 && exit 1'
ADAPTER
  sed -i "s|__BUCKET__|$S3_BUCKET|; s|__PREFIX__|$S3_PREFIX|" "$COMMAND_ADAPTER_CONFIG"
fi

# --- Run the restore ------------------------------------------------------
echo ""
echo "Starting restore — this will take a while:"
echo "  mainnet ~3 hours"
echo "  testnet ~2 hours with --downloader=s5cmd, ~4 hours with --downloader=debugger"
echo ""

aptos-debugger aptos-db restore bootstrap-db \
  --command-adapter-config "$COMMAND_ADAPTER_CONFIG" \
  --metadata-cache-dir "$METADATA_CACHE_DIR" \
  --target-db-dir "$TARGET_DB_DIR" \
  --target-version "$TARGET_VERSION" \
  --trust-waypoint "$TRUST_WAYPOINT" \
  --ledger-history-start-version 0 \
  --replay-all

if [ "$DOWNLOADER" = "s5cmd" ]; then
  rm -rf "$LOCAL_METADATA_DIR"
fi

echo ""
echo "Restore complete!"
echo ""
echo "Database restored to: $TARGET_DB_DIR"
echo ""
echo "Next steps:"
echo "1. Move the restored data to your node's data directory:"
echo "   mv $TARGET_DB_DIR /your/node/data/dir/"
echo ""
echo "2. Genesis files for $NETWORK are colocated in:"
echo "   $SCRIPT_DIR/$NETWORK/"
echo "   (genesis.blob, waypoint.txt, genesis_waypoint.txt)"
echo ""
echo "3. Use the appropriate configs/fullnode.yaml or configs/archival-fullnode.yaml"
echo "   from $NETWORK/configs/"
echo ""
echo "4. Start your node!"
