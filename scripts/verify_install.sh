#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd "${SCRIPT_DIR}/.." && pwd -P)
CONDA_BIN=${CONDA_EXE:-$(command -v conda || true)}
MODE=${1:-}

if [[ -z "${CONDA_BIN}" ]]; then
    echo "conda was not found." >&2
    exit 1
fi
if [[ -n "${MODE}" && "${MODE}" != "--render" ]]; then
    echo "Usage: $0 [--render]" >&2
    exit 2
fi

for path in \
    "${ROOT}/Zero-WAM/wan_va/wan_va_server.py" \
    "${ROOT}/Zero-WAM/evaluation/robotwin/run_two_gpu_eval.sh" \
    "${ROOT}/RoboTwin/envs/place_object_scale.py" \
    "${ROOT}/RoboTwin/task_config/demo_clean.yml"; do
    test -e "${path}" || { echo "Missing: ${path}" >&2; exit 1; }
done

"${CONDA_BIN}" run -n zerowam python -c \
    'import torch, diffusers, transformers; print("Zero-WAM Python OK", torch.__version__)'
ROBOTWIN_ROOT="${ROOT}/RoboTwin" \
PYTHONPATH="${ROOT}/Zero-WAM:${ROOT}/RoboTwin" \
"${CONDA_BIN}" run -n RoboTwin python -c \
    'import sapien, mplib, curobo; print("RoboTwin Python OK")'

checkpoint="${ROOT}/Zero-WAM/checkpoints/zero-wam-posttrain-robotwin"
assets="${ROOT}/RoboTwin/assets"
latent_root="${ROOT}/Zero-WAM/data/HumanGen/human_latents/robotwin"

test -f "${checkpoint}/transformer/config.json" \
    && echo "Checkpoint OK" || echo "Checkpoint not downloaded"
test -d "${assets}/embodiments" -a -d "${assets}/objects" \
    && echo "RoboTwin assets OK" || echo "RoboTwin assets not downloaded"
find "${latent_root}" -type f -name '*.pth' -print -quit 2>/dev/null | grep -q . \
    && echo "ICL latents OK" || echo "ICL latents not downloaded"

if [[ "${MODE}" == "--render" ]]; then
    CUDA_VISIBLE_DEVICES=${GPU_ID:-0} \
    ROBOTWIN_ROOT="${ROOT}/RoboTwin" \
    PYTHONPATH="${ROOT}/Zero-WAM:${ROOT}/RoboTwin" \
    "${CONDA_BIN}" run --no-capture-output -n RoboTwin \
        python "${ROOT}/Zero-WAM/evaluation/robotwin/test_render.py"
fi

echo "Verification complete."
