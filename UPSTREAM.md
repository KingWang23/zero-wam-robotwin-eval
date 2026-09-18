# Upstream Sources

## Zero-WAM

- Repository: https://github.com/robbyant-research/Zero-WAM
- Snapshot: `08e2c4ae41e2b63573a299825cebe6753481407c`
- License: see `Zero-WAM/LICENSE.txt`

The snapshot includes local RoboTwin evaluation launchers, VAE placement,
visualization, deterministic prompt replay, and memory-management changes.

## RoboTwin

- Repository: https://github.com/RoboTwin-Platform/RoboTwin
- Snapshot: `2eeec322d95799f537cbfe5f291a8220d965ccb8`
- License: see `RoboTwin/LICENSE`

The snapshot includes the Zero-WAM paper's success-condition changes for
`move_stapler_pad` and `stamp_seal`.

## Curobo

- Repository: https://github.com/NVlabs/curobo
- Install revision: `d64c4b005459db10c5dd867d8b30a87d5bda9bdb`
- Not vendored; installed by `scripts/bootstrap_envs.sh`.

Each component remains subject to its upstream license and dependency terms.
