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

| Script | Description |
|--------|-------------|
| `l1_restore.sh` | Restore L1 node data from Movement Labs backups |
| `l2_restore.sh` | Restore L2 node data from Movement Labs backups (deperecated since l1 migration) |

### L1 Database Restore

To bootstrap a fullnode or archival node with existing blockchain data:

```bash
# For testnet (default)
./l1_restore.sh testnet ./data

# For mainnet
./l1_restore.sh mainnet ./data
```

**Prerequisites:**

- [restic](https://restic.net/) installed
- Sufficient disk space (mainnet ~700GB, testnet ~260GB)

The backups are updated hourly and maintain 14 days of snapshot history.

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
../l1_restore.sh mainnet ../data

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
