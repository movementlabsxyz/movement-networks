# Movement Networks

Configuration files and genesis data for connecting to Movement Network environments.

## Networks

| Network | Status | Description |
|---------|--------|-------------|
| `mainnet/` | Active | Movement mainnet - production network |
| `testnet/` | Active | Movement testnet - community testing and validation |
| `devnet/` | Active | Movement devnet - internal testing by Movement Labs |

## Files Per Network

Each network directory contains:

| File | Description |
|------|-------------|
| `genesis.blob` | Genesis block data |
| `waypoint.txt` | Current waypoint for state sync |
| `genesis_waypoint.txt` | Genesis waypoint |
| `configs/fullnode.yaml` | Standard public fullnode configuration |
| `configs/archival-fullnode.yaml` | Archival fullnode configuration (complete history) |

## Restore Scripts

| Script                | Description                                                                |
|-----------------------|----------------------------------------------------------------------------|
| `database-restore.sh` | **Recommended.** Native restore from continuous backup via aptos-debugger. |
| `l1_restore.sh`       | Deprecated. Restic restore from the legacy snapshot pipeline.              |
| `l2_restore.sh`       | Deprecated (since L1 migration).                                           |

### Database Restore

To bootstrap a fullnode or archival node with existing blockchain data:

```bash
# For testnet (default)
./database-restore.sh testnet ./data

# For mainnet
./database-restore.sh mainnet ./data

# Wipe an existing restore target and start fresh
./database-restore.sh mainnet ./data --force

# Use s5cmd for a much faster metadata phase (requires s5cmd installed)
./database-restore.sh testnet ./data --downloader=s5cmd
```

**Prerequisites:**

- `aptos-debugger` from the [latest movementlabsxyz/aptos-core release](https://github.com/movementlabsxyz/aptos-core/releases/latest)
- [AWS CLI](https://aws.amazon.com/cli/) (`aws s3` is used for anonymous reads against the public backup bucket — no AWS credentials required)
- [s5cmd](https://github.com/peak/s5cmd) — only required if you pass `--downloader=s5cmd`. The default `--downloader=debugger` path uses aws-cli alone.
- Sufficient disk space:

  | Network | Restore size | `--downloader=s5cmd` | `--downloader=debugger` (default) |
  |---------|--------------|----------------------|-----------------------------------|
  | mainnet | ~700 GB      | ~3 hours             | ~3 hours                          |
  | testnet | ~260 GB      | ~2 hours             | ~4 hours                          |

  (Mainnet's metadata index is small and barely affected by metadata-fetch speed; testnet's is much larger.)

The script reads the trust waypoint from `<network>/waypoint.txt` in this directory and auto-discovers the latest restore target version from the continuous-backup bucket. The resulting database serves the full chain from genesis (`oldest_ledger_version: 0`).

For the legacy restic-based flow, see [`l1_restore.sh`](./l1_restore.sh) (deprecated).

## Node Types

### Standard Fullnode

A standard public fullnode (PFN) syncs recent blockchain state and maintains pruned history.

- Use `configs/fullnode.yaml` configuration
- Faster initial sync via state snapshots
- Lower storage requirements

### Archival Fullnode

An archival fullnode maintains complete blockchain history from genesis by disabling ledger pruning.

- Use `configs/archival-fullnode.yaml` configuration
- Complete transaction history access
- Required for historical queries and indexers
- Higher storage requirements

## Documentation

For detailed deployment instructions, see the Movement documentation:

- [Full Node Deployment](https://docs.movementnetwork.xyz/general/nodes/full-node/run/deploy)
- [Archival Node Deployment](https://docs.movementnetwork.xyz/general/nodes/archival-node/run/deploy)

## Quick Start

```bash
# 1. Clone this repository
git clone https://github.com/movementlabsxyz/movement-networks.git
cd movement-networks

# 2. Choose your network (mainnet or testnet)
cd mainnet  # or testnet

# 3. (Optional) Restore existing data for faster sync
../database-restore.sh mainnet ../data

# 4. Run with Docker
docker run --pull=always \
  --rm -p 8080:8080 -p 9101:9101 -p 6180:6180 \
  -v $(pwd):/opt/aptos \
  -v $(pwd)/../data:/opt/aptos/data \
  --workdir /opt/aptos \
  --name=movement-fullnode \
  ghcr.io/movementlabsxyz/aptos-node:f24a5bc \
  -f /opt/aptos/configs/fullnode.yaml
```
