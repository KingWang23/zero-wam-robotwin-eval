#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
ZERO_WAM_ROOT=$(cd "${SCRIPT_DIR}/../.." && pwd -P)

ROBOTWIN_ROOT=${ROBOTWIN_ROOT:-$(cd "${ZERO_WAM_ROOT}/../RoboTwin" && pwd -P)}
MODEL_PATH=${MODEL_PATH:-${ZERO_WAM_ROOT}/checkpoints/zero-wam-posttrain-robotwin}
ZERO_WAM_ENV=${ZERO_WAM_ENV:-zerowam}
ROBOTWIN_ENV=${ROBOTWIN_ENV:-RoboTwin}
GPU_ID=${GPU_ID:-0}
SERVER_GPU_ID=${SERVER_GPU_ID:-${GPU_ID}}
CLIENT_GPU_ID=${CLIENT_GPU_ID:-${GPU_ID}}
PORT=${PORT:-29056}
MASTER_PORT=${MASTER_PORT:-29061}
SERVER_START_TIMEOUT=${SERVER_START_TIMEOUT:-900}
TASK_NAME=${1:-place_object_scale}
TEST_NUM=${TEST_NUM:-1}
MAX_STEPS=${MAX_STEPS:-0}
SEED=${SEED:-0}
EVAL_MODE=${EVAL_MODE:-icl}
SAVE_IMAGINED_VIDEO=${SAVE_IMAGINED_VIDEO:-1}
PROMPT_MANIFEST=${PROMPT_MANIFEST:-}
ENABLE_OFFLOAD=${ZERO_WAM_ENABLE_OFFLOAD:-1}
if [[ -n "${VAE_DEVICE:-}" ]]; then
    VAE_DEVICE=${VAE_DEVICE}
elif [[ -n "${ZERO_WAM_VAE_DEVICE:-}" ]]; then
    VAE_DEVICE=${ZERO_WAM_VAE_DEVICE}
elif [[ "${ENABLE_OFFLOAD,,}" =~ ^(0|false|no|off)$ ]]; then
    VAE_DEVICE=cuda
else
    VAE_DEVICE=cpu
fi

case "${VAE_DEVICE,,}" in
    cpu) VAE_DEVICE=cpu ;;
    gpu|cuda) VAE_DEVICE=cuda ;;
    *)
        echo "VAE_DEVICE must be 'cpu' or 'gpu', got: ${VAE_DEVICE}" >&2
        exit 1
        ;;
esac

case "${EVAL_MODE}" in
    icl)
        USE_ICL=1
        ICL_CFG=${ICL_CFG:-5}
        TARGET_TEXT_CFG=${TARGET_TEXT_CFG:--1}
        ;;
    no_icl)
        USE_ICL=0
        ICL_CFG=${ICL_CFG:-1}
        TARGET_TEXT_CFG=${TARGET_TEXT_CFG:-1}
        ;;
    *)
        echo "EVAL_MODE must be 'icl' or 'no_icl', got: ${EVAL_MODE}" >&2
        exit 1
        ;;
esac
SAVE_ROOT=${SAVE_ROOT:-${ZERO_WAM_ROOT}/results/${EVAL_MODE}}

CONDA_BIN=${CONDA_EXE:-$(command -v conda || true)}
if [[ -z "${CONDA_BIN}" ]]; then
    echo "conda was not found; set CONDA_EXE to the conda executable." >&2
    exit 1
fi

for required_path in \
    "${MODEL_PATH}/transformer/config.json" \
    "${MODEL_PATH}/vae/config.json" \
    "${MODEL_PATH}/text_encoder/config.json" \
    "${ROBOTWIN_ROOT}/policy/ACT/deploy_policy.yml" \
    "${ROBOTWIN_ROOT}/envs/${TASK_NAME}.py"; do
    if [[ ! -e "${required_path}" ]]; then
        echo "Required path is missing: ${required_path}" >&2
        exit 1
    fi
done

mkdir -p "${ZERO_WAM_ROOT}/logs" "${SAVE_ROOT}"
CACHE_ROOT=${CACHE_ROOT:-${ZERO_WAM_ROOT}/.cache}
mkdir -p "${CACHE_ROOT}/matplotlib" "${CACHE_ROOT}/fontconfig"
SERVER_LOG="${ZERO_WAM_ROOT}/logs/server_single_${TASK_NAME}_$(date +%Y%m%d_%H%M%S).log"
SERVER_PID=""

cleanup() {
    status=$?
    trap - EXIT INT TERM
    if [[ -n "${SERVER_PID}" ]]; then
        kill -- "-${SERVER_PID}" 2>/dev/null || true
        wait "${SERVER_PID}" 2>/dev/null || true
    fi
    exit "${status}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if curl --fail --silent --max-time 1 \
    "http://127.0.0.1:${PORT}/healthz" >/dev/null; then
    echo "Port ${PORT} already has a Zero-WAM server. Stop it or set another PORT." >&2
    exit 1
fi

echo "Starting Zero-WAM server on GPU ${SERVER_GPU_ID}, port ${PORT}..."
CUDA_VISIBLE_DEVICES="${SERVER_GPU_ID}" MODEL_PATH="${MODEL_PATH}" PORT="${PORT}" \
MASTER_PORT="${MASTER_PORT}" \
PYTORCH_CUDA_ALLOC_CONF="${PYTORCH_CUDA_ALLOC_CONF:-expandable_segments:True}" \
ZERO_WAM_ENABLE_OFFLOAD="${ENABLE_OFFLOAD}" \
ZERO_WAM_VAE_DEVICE="${VAE_DEVICE}" \
setsid "${CONDA_BIN}" run --no-capture-output -n "${ZERO_WAM_ENV}" \
    bash "${SCRIPT_DIR}/launch_server.sh" >"${SERVER_LOG}" 2>&1 &
SERVER_PID=$!

deadline=$((SECONDS + SERVER_START_TIMEOUT))
while ((SECONDS < deadline)); do
    if curl --fail --silent --max-time 1 \
        "http://127.0.0.1:${PORT}/healthz" >/dev/null; then
        break
    fi
    if ! kill -0 "${SERVER_PID}" 2>/dev/null; then
        echo "Zero-WAM server exited during startup. Last log lines:" >&2
        tail -80 "${SERVER_LOG}" >&2
        exit 1
    fi
    sleep 5
done

if ! curl --fail --silent --max-time 1 \
    "http://127.0.0.1:${PORT}/healthz" >/dev/null; then
    echo "Zero-WAM server did not become ready within ${SERVER_START_TIMEOUT}s." >&2
    tail -80 "${SERVER_LOG}" >&2
    exit 1
fi

sleep 2
if ! kill -0 "${SERVER_PID}" 2>/dev/null; then
    echo "Zero-WAM server exited after reporting ready. Last log lines:" >&2
    tail -80 "${SERVER_LOG}" >&2
    exit 1
fi

echo "Server ready. Evaluating ${TASK_NAME} for ${TEST_NUM} trial(s) on GPU ${CLIENT_GPU_ID}..."
CUDA_VISIBLE_DEVICES="${CLIENT_GPU_ID}" ROBOTWIN_ROOT="${ROBOTWIN_ROOT}" \
MODEL_PATH="${MODEL_PATH}" PORT="${PORT}" TEST_NUM="${TEST_NUM}" SEED="${SEED}" \
MAX_STEPS="${MAX_STEPS}" \
USE_ICL="${USE_ICL}" ICL_CFG="${ICL_CFG}" TARGET_TEXT_CFG="${TARGET_TEXT_CFG}" \
SAVE_IMAGINED_VIDEO="${SAVE_IMAGINED_VIDEO}" \
PROMPT_MANIFEST="${PROMPT_MANIFEST}" \
MPLCONFIGDIR="${CACHE_ROOT}/matplotlib" XDG_CACHE_HOME="${CACHE_ROOT}" \
FONTCONFIG_FILE="${FONTCONFIG_FILE:-/etc/fonts/fonts.conf}" \
PYTHONUNBUFFERED=1 \
"${CONDA_BIN}" run --no-capture-output -n "${ROBOTWIN_ENV}" \
    bash "${SCRIPT_DIR}/launch_client.sh" "${SAVE_ROOT}" "${TASK_NAME}"

echo "Evaluation complete (${EVAL_MODE}). Results: ${SAVE_ROOT}"
echo "Server log: ${SERVER_LOG}"
