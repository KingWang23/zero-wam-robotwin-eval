#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd "${SCRIPT_DIR}/.." && pwd -P)
CONDA_BIN=${CONDA_EXE:-$(command -v conda || true)}

if [[ -z "${CONDA_BIN}" ]]; then
    echo "conda was not found. Install Miniconda first." >&2
    exit 1
fi

create_or_update_env() {
    local name=$1
    local file=$2
    if "${CONDA_BIN}" env list | awk '{print $1}' | grep -Fxq "${name}"; then
        "${CONDA_BIN}" env update -n "${name}" -f "${file}"
    else
        "${CONDA_BIN}" env create -f "${file}"
    fi
}

create_or_update_env zerowam "${ROOT}/environments/zerowam.yml"
create_or_update_env RoboTwin "${ROOT}/environments/robotwin.yml"

echo "Installing Zero-WAM dependencies..."
"${CONDA_BIN}" run --no-capture-output -n zerowam \
    python -m pip install -r "${ROOT}/Zero-WAM/requirements.txt" --no-build-isolation
"${CONDA_BIN}" run --no-capture-output -n zerowam \
    python -m pip install -e "${ROOT}/Zero-WAM" --no-build-isolation

echo "Installing RoboTwin dependencies..."
"${CONDA_BIN}" run --no-capture-output -n RoboTwin \
    python -m pip install -r "${ROOT}/RoboTwin/script/requirements.txt"
"${CONDA_BIN}" run --no-capture-output -n RoboTwin \
    python -m pip install "git+https://github.com/facebookresearch/pytorch3d.git@stable"

CUROBO_ROOT="${ROOT}/third_party/curobo"
if [[ ! -d "${CUROBO_ROOT}/.git" ]]; then
    mkdir -p "${ROOT}/third_party"
    git clone https://github.com/NVlabs/curobo.git "${CUROBO_ROOT}"
fi
git -C "${CUROBO_ROOT}" fetch --all --tags
git -C "${CUROBO_ROOT}" checkout d64c4b005459db10c5dd867d8b30a87d5bda9bdb

ROBOTWIN_PREFIX=$("${CONDA_BIN}" run -n RoboTwin python -c \
    'import sys; print(sys.prefix)')
CUDA_HOME="${ROBOTWIN_PREFIX}" \
PATH="${ROBOTWIN_PREFIX}/bin:${PATH}" \
"${CONDA_BIN}" run --no-capture-output -n RoboTwin \
    python -m pip install -e "${CUROBO_ROOT}" --no-build-isolation

"${CONDA_BIN}" run --no-capture-output -n RoboTwin \
    python "${SCRIPT_DIR}/patch_robotwin_dependencies.py"

echo
echo "Environment installation complete."
echo "Next: bash scripts/download_runtime.sh all"
