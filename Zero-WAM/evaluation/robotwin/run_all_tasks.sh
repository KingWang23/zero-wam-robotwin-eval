#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
ZERO_WAM_ROOT=$(cd "${SCRIPT_DIR}/../.." && pwd -P)
trap 'exit 130' INT
trap 'exit 143' TERM

MODE=${1:-icl}
TASKS=(
    place_object_scale
    stamp_seal
    open_microwave
    move_stapler_pad
    place_bread_basket
    place_empty_cup
    stack_blocks_three
)

case "${MODE}" in
    icl)
        MODES=(icl)
        ;;
    no_icl)
        MODES=(no_icl)
        ;;
    both)
        MODES=(icl no_icl)
        ;;
    *)
        echo "Usage: $0 [icl|no_icl|both]" >&2
        exit 2
        ;;
esac

REQUESTED_SAVE_ROOT=${SAVE_ROOT:-}
FAILED=()
COMPLETED=0
TOTAL=$((${#MODES[@]} * ${#TASKS[@]}))

for mode in "${MODES[@]}"; do
    case "${mode}" in
        icl) runner="${SCRIPT_DIR}/run_with_icl.sh" ;;
        no_icl) runner="${SCRIPT_DIR}/run_without_icl.sh" ;;
    esac

    if [[ -n "${REQUESTED_SAVE_ROOT}" ]]; then
        if [[ "${MODE}" == "both" ]]; then
            mode_save_root="${REQUESTED_SAVE_ROOT%/}/${mode}"
        else
            mode_save_root="${REQUESTED_SAVE_ROOT}"
        fi
    else
        mode_save_root="${ZERO_WAM_ROOT}/results/${mode}"
    fi

    for task in "${TASKS[@]}"; do
        index=$((COMPLETED + 1))
        echo
        echo "========== [${index}/${TOTAL}] mode=${mode}, task=${task} =========="

        if SAVE_ROOT="${mode_save_root}" bash "${runner}" "${task}"; then
            echo "DONE: mode=${mode}, task=${task}"
        else
            status=$?
            echo "FAILED (${status}): mode=${mode}, task=${task}" >&2
            FAILED+=("${mode}:${task}:${status}")
        fi
        COMPLETED=$((COMPLETED + 1))
    done
done

echo
echo "========== Batch summary =========="
echo "Completed: ${COMPLETED}/${TOTAL}"
if ((${#FAILED[@]} == 0)); then
    echo "All evaluation commands completed. Check res.json for task success rates."
    exit 0
fi

echo "Failed evaluations:" >&2
printf '  %s\n' "${FAILED[@]}" >&2
exit 1
