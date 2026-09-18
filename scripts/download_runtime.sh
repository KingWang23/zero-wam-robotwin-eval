#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd "${SCRIPT_DIR}/.." && pwd -P)
CONDA_BIN=${CONDA_EXE:-$(command -v conda || true)}
MODE=${1:-all}

if [[ -z "${CONDA_BIN}" ]]; then
    echo "conda was not found." >&2
    exit 1
fi
if [[ ! "${MODE}" =~ ^(all|assets|checkpoint|icl)$ ]]; then
    echo "Usage: $0 [all|assets|checkpoint|icl]" >&2
    exit 2
fi

download_assets() {
    echo "Downloading and extracting RoboTwin assets..."
    (
        cd "${ROOT}/RoboTwin"
        "${CONDA_BIN}" run --no-capture-output -n RoboTwin \
            bash script/_download_assets.sh
    )
}

download_checkpoint() {
    echo "Downloading Zero-WAM Robotwin checkpoint..."
    "${CONDA_BIN}" run --no-capture-output -n zerowam \
        hf download robbyant-research/zero-wam-posttrain-robotwin \
        --local-dir "${ROOT}/Zero-WAM/checkpoints/zero-wam-posttrain-robotwin"
}

download_icl() {
    echo "Downloading minimal HumanGen Robotwin ICL data..."
    "${CONDA_BIN}" run --no-capture-output -n zerowam \
        hf download Robbyant-Research/HumanGen \
        --repo-type dataset \
        --local-dir "${ROOT}/Zero-WAM/data/HumanGen" \
        --include "icl_configs/*" \
        --include "robotwin_data/**" \
        --include "human_latents/robotwin/**"
}

case "${MODE}" in
    all)
        download_assets
        download_checkpoint
        download_icl
        ;;
    assets) download_assets ;;
    checkpoint) download_checkpoint ;;
    icl) download_icl ;;
esac

echo "Download complete. Run: bash scripts/verify_install.sh --render"
