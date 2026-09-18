#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
ZERO_WAM_ROOT=$(cd "${SCRIPT_DIR}/../.." && pwd -P)

export EVAL_MODE=icl
export ICL_CFG=${ICL_CFG:-5}
export TARGET_TEXT_CFG=${TARGET_TEXT_CFG:--1}
export SAVE_IMAGINED_VIDEO=${SAVE_IMAGINED_VIDEO:-1}
export SAVE_ROOT=${SAVE_ROOT:-${ZERO_WAM_ROOT}/results/icl}

exec bash "${SCRIPT_DIR}/run_single_eval.sh" "${1:-place_object_scale}"
