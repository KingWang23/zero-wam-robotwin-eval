#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
ZERO_WAM_ROOT=$(cd "${SCRIPT_DIR}/../.." && pwd -P)
ROBOTWIN_ROOT=${ROBOTWIN_ROOT:-$(cd "${ZERO_WAM_ROOT}/../RoboTwin" && pwd -P)}
MODEL_PATH=${MODEL_PATH:-${ZERO_WAM_ROOT}/checkpoints/zero-wam-posttrain-robotwin}
ZERO_WAM_ENV=${ZERO_WAM_ENV:-zerowam}
ROBOTWIN_ENV=${ROBOTWIN_ENV:-RoboTwin}

MODE=${1:-icl}
GPU_IDS=${GPU_IDS:-0,1}
START_PORT=${START_PORT:-29056}
START_MASTER_PORT=${START_MASTER_PORT:-29061}
SERVER_START_TIMEOUT=${SERVER_START_TIMEOUT:-900}
TEST_NUM=${TEST_NUM:-1}
MAX_STEPS=${MAX_STEPS:-0}
SEED=${SEED:-0}
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
REQUESTED_SAVE_ROOT=${SAVE_ROOT:-}
CACHE_ROOT=${CACHE_ROOT:-${ZERO_WAM_ROOT}/.cache}
LOG_ROOT=${LOG_ROOT:-${ZERO_WAM_ROOT}/logs}

DEFAULT_TASKS=(
    place_object_scale
    stamp_seal
    open_microwave
    move_stapler_pad
    place_bread_basket
    place_empty_cup
    stack_blocks_three
)
if [[ -n "${TASK_NAMES:-}" ]]; then
    IFS=',' read -r -a TASKS <<< "${TASK_NAMES}"
else
    TASKS=("${DEFAULT_TASKS[@]}")
fi
if ((${#TASKS[@]} == 0)); then
    echo "TASK_NAMES did not contain any task names." >&2
    exit 2
fi

case "${MODE}" in
    icl) MODES=(icl) ;;
    no_icl) MODES=(no_icl) ;;
    both) MODES=(icl no_icl) ;;
    *)
        echo "Usage: $0 [icl|no_icl|both]" >&2
        exit 2
        ;;
esac

case "${VAE_DEVICE,,}" in
    cpu) VAE_DEVICE=cpu ;;
    gpu|cuda) VAE_DEVICE=cuda ;;
    *)
        echo "VAE_DEVICE must be 'cpu' or 'gpu', got: ${VAE_DEVICE}" >&2
        exit 2
        ;;
esac

IFS=',' read -r -a GPUS <<< "${GPU_IDS}"
if ((${#GPUS[@]} != 2)) || [[ -z "${GPUS[0]}" || -z "${GPUS[1]}" ]]; then
    echo "GPU_IDS must contain exactly two GPU IDs, for example GPU_IDS=0,1." >&2
    exit 2
fi
if [[ "${GPUS[0]}" == "${GPUS[1]}" ]]; then
    echo "GPU_IDS must contain two different GPU IDs." >&2
    exit 2
fi

CONDA_BIN=${CONDA_EXE:-$(command -v conda || true)}
if [[ -z "${CONDA_BIN}" ]]; then
    echo "conda was not found; set CONDA_EXE to the conda executable." >&2
    exit 1
fi

for required_path in \
    "${MODEL_PATH}/transformer/config.json" \
    "${MODEL_PATH}/vae/config.json" \
    "${MODEL_PATH}/text_encoder/config.json" \
    "${ROBOTWIN_ROOT}/policy/ACT/deploy_policy.yml"; do
    if [[ ! -e "${required_path}" ]]; then
        echo "Required path is missing: ${required_path}" >&2
        exit 1
    fi
done
for task in "${TASKS[@]}"; do
    if [[ -z "${task}" ]]; then
        echo "TASK_NAMES contains an empty task name." >&2
        exit 2
    fi
    if [[ ! -e "${ROBOTWIN_ROOT}/envs/${task}.py" ]]; then
        echo "Required task is missing: ${ROBOTWIN_ROOT}/envs/${task}.py" >&2
        exit 1
    fi
done

mkdir -p \
    "${LOG_ROOT}" \
    "${CACHE_ROOT}/matplotlib" \
    "${CACHE_ROOT}/fontconfig" \
    "${CACHE_ROOT}/torchinductor/gpu_${GPUS[0]}" \
    "${CACHE_ROOT}/torchinductor/gpu_${GPUS[1]}"

BATCH_TIME=$(date +%Y%m%d_%H%M%S)
SERVER_PIDS=()
WORKER_PIDS=()

cleanup() {
    status=$?
    trap - EXIT INT TERM
    for pid in "${WORKER_PIDS[@]}"; do
        kill "${pid}" 2>/dev/null || true
    done
    for pid in "${SERVER_PIDS[@]}"; do
        kill -- "-${pid}" 2>/dev/null || true
    done
    for pid in "${WORKER_PIDS[@]}" "${SERVER_PIDS[@]}"; do
        wait "${pid}" 2>/dev/null || true
    done
    exit "${status}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

for worker in 0 1; do
    gpu=${GPUS[$worker]}
    port=$((START_PORT + worker))
    master_port=$((START_MASTER_PORT + worker))
    server_log="${LOG_ROOT}/server_two_gpu_w${worker}_gpu${gpu}_${BATCH_TIME}.log"

    if curl --fail --silent --max-time 1 \
        "http://127.0.0.1:${port}/healthz" >/dev/null; then
        echo "Port ${port} already has a Zero-WAM server." >&2
        exit 1
    fi

    echo "Starting worker ${worker}: Zero-WAM + RoboTwin on GPU ${gpu}, port ${port}, VAE=${VAE_DEVICE}"
    CUDA_VISIBLE_DEVICES="${gpu}" \
    MODEL_PATH="${MODEL_PATH}" \
    PORT="${port}" \
    MASTER_PORT="${master_port}" \
    PYTORCH_CUDA_ALLOC_CONF="${PYTORCH_CUDA_ALLOC_CONF:-expandable_segments:True}" \
    ZERO_WAM_ENABLE_OFFLOAD="${ENABLE_OFFLOAD}" \
    ZERO_WAM_VAE_DEVICE="${VAE_DEVICE}" \
    TORCHINDUCTOR_CACHE_DIR="${CACHE_ROOT}/torchinductor/gpu_${gpu}" \
    setsid "${CONDA_BIN}" run --no-capture-output -n "${ZERO_WAM_ENV}" \
        bash "${SCRIPT_DIR}/launch_server.sh" >"${server_log}" 2>&1 &
    SERVER_PIDS+=("$!")
done

deadline=$((SECONDS + SERVER_START_TIMEOUT))
while ((SECONDS < deadline)); do
    ready=1
    for worker in 0 1; do
        if ! curl --fail --silent --max-time 1 \
            "http://127.0.0.1:$((START_PORT + worker))/healthz" >/dev/null; then
            ready=0
        fi
        if ! kill -0 "${SERVER_PIDS[$worker]}" 2>/dev/null; then
            echo "Worker ${worker} Zero-WAM server exited during startup." >&2
            tail -80 "${LOG_ROOT}/server_two_gpu_w${worker}_gpu${GPUS[$worker]}_${BATCH_TIME}.log" >&2
            exit 1
        fi
    done
    ((ready)) && break
    sleep 5
done

for worker in 0 1; do
    if ! curl --fail --silent --max-time 1 \
        "http://127.0.0.1:$((START_PORT + worker))/healthz" >/dev/null; then
        echo "Worker ${worker} server was not ready within ${SERVER_START_TIMEOUT}s." >&2
        exit 1
    fi
done
echo "Both Zero-WAM servers are ready. Starting two parallel RoboTwin workers."

run_worker() {
    local worker=$1
    local gpu=${GPUS[$worker]}
    local port=$((START_PORT + worker))
    local failures=0
    local child_pid=""

    trap '[[ -n "${child_pid}" ]] && kill -- "-${child_pid}" 2>/dev/null || true; exit 130' INT
    trap '[[ -n "${child_pid}" ]] && kill -- "-${child_pid}" 2>/dev/null || true; exit 143' TERM

    for mode in "${MODES[@]}"; do
        local task_index=0
        if [[ "${mode}" == "icl" ]]; then
            use_icl=1
            icl_cfg=${ICL_GUIDANCE_SCALE:-5}
            text_cfg=${ICL_TEXT_GUIDANCE_SCALE:--1}
        else
            use_icl=0
            icl_cfg=${NO_ICL_GUIDANCE_SCALE:-1}
            text_cfg=${NO_ICL_TEXT_GUIDANCE_SCALE:-1}
        fi

        if [[ -n "${REQUESTED_SAVE_ROOT}" ]]; then
            if [[ "${MODE}" == "both" ]]; then
                mode_save_root="${REQUESTED_SAVE_ROOT%/}/${mode}"
            else
                mode_save_root="${REQUESTED_SAVE_ROOT}"
            fi
        else
            mode_save_root="${ZERO_WAM_ROOT}/results/${mode}"
        fi
        mkdir -p "${mode_save_root}"

        for task in "${TASKS[@]}"; do
            if ((task_index % 2 != worker)); then
                task_index=$((task_index + 1))
                continue
            fi

            client_log="${LOG_ROOT}/client_two_gpu_w${worker}_gpu${gpu}_${mode}_${task}_${BATCH_TIME}.log"
            echo "[worker ${worker}/GPU ${gpu}] START mode=${mode}, task=${task}, log=${client_log}"
            CUDA_VISIBLE_DEVICES="${gpu}" \
            ROBOTWIN_ROOT="${ROBOTWIN_ROOT}" \
            MODEL_PATH="${MODEL_PATH}" \
            PORT="${port}" \
            TEST_NUM="${TEST_NUM}" \
            SEED="${SEED}" \
            MAX_STEPS="${MAX_STEPS}" \
            USE_ICL="${use_icl}" \
            ICL_CFG="${icl_cfg}" \
            TARGET_TEXT_CFG="${text_cfg}" \
            SAVE_IMAGINED_VIDEO="${SAVE_IMAGINED_VIDEO}" \
            PROMPT_MANIFEST="${PROMPT_MANIFEST}" \
            MPLCONFIGDIR="${CACHE_ROOT}/matplotlib" \
            XDG_CACHE_HOME="${CACHE_ROOT}" \
            FONTCONFIG_FILE="${FONTCONFIG_FILE:-/etc/fonts/fonts.conf}" \
            PYTHONUNBUFFERED=1 \
            setsid "${CONDA_BIN}" run --no-capture-output -n "${ROBOTWIN_ENV}" \
                bash "${SCRIPT_DIR}/launch_client.sh" "${mode_save_root}" "${task}" \
                >"${client_log}" 2>&1 &
            child_pid=$!
            if wait "${child_pid}"; then
                echo "[worker ${worker}/GPU ${gpu}] DONE mode=${mode}, task=${task}"
            else
                status=$?
                echo "[worker ${worker}/GPU ${gpu}] FAILED(${status}) mode=${mode}, task=${task}" >&2
                failures=$((failures + 1))
            fi
            child_pid=""
            task_index=$((task_index + 1))
        done
    done
    return "${failures}"
}

run_worker 0 &
WORKER_PIDS+=("$!")
run_worker 1 &
WORKER_PIDS+=("$!")

status=0
for pid in "${WORKER_PIDS[@]}"; do
    wait "${pid}" || status=1
done
WORKER_PIDS=()

if ((status == 0)); then
    echo "All two-GPU evaluation commands completed. Check res.json for success rates."
else
    echo "Some evaluation commands failed. Check client_two_gpu logs under ${LOG_ROOT}." >&2
fi
exit "${status}"
