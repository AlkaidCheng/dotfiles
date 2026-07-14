#!/bin/bash
#
# test_conda_environment.sh
#
# Acceptance test for create_conda_environment.sh, meant to be run on a real
# GPU machine. It (optionally) runs the installer, then validates that the
# resulting environment is correct:
#
#   * the environment exists and activates;
#   * every installed deep-learning framework actually sees and uses the GPU;
#   * there is exactly ONE CUDA stack (no conda/pip mix, no duplicate majors);
#   * the requested science/grid packages import.
#
# It logs the total time taken (install + validation) and the storage used by
# the environment and the Miniforge base.
#
# Usage:
#   # install with framework flags, time it, then validate + measure:
#   ./test_conda_environment.sh -d ~/conda -n gputest -- --pytorch --tensorflow --jax
#
#   # validate + measure an environment that already exists:
#   ./test_conda_environment.sh -d ~/conda -n gputest --validate-only
#
# Everything after `--` is forwarded verbatim to create_conda_environment.sh
# (with -d/-n added automatically).

set -o pipefail

CONDA_ENV_NAME="envbase"
CONDADIR=""
CONDADIR_SET=false
VALIDATE_ONLY=false
FORWARD=()

# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #
die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "INFO: $*"; }
warn() { echo "WARNING: $*" >&2; }

PASS=0
FAIL=0
# check <ok?0/1> <label>
check() {
    if [[ "$1" -eq 0 ]]; then
        echo "  PASS  $2"; PASS=$((PASS + 1))
    else
        echo "  FAIL  $2"; FAIL=$((FAIL + 1))
    fi
}

usage() {
    cat <<EOF
Usage: $0 -d DIR [-n NAME] [--validate-only] [-- <installer flags>]

  -d, --dir DIR      Conda base directory (same as the installer's -d) [required]
  -n, --name NAME    Environment name (default: $CONDA_ENV_NAME)
      --validate-only  Skip running the installer; validate an existing env
  -h, --help         Show this help
  --                 Forward the remaining flags to create_conda_environment.sh
EOF
}

# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #
main() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--dir)  [[ -n "$2" ]] || die "missing value for $1"; CONDADIR="$2"; CONDADIR_SET=true; shift ;;
            -n|--name) [[ -n "$2" ]] || die "missing value for $1"; CONDA_ENV_NAME="$2"; shift ;;
            --validate-only) VALIDATE_ONLY=true ;;
            -h|--help) usage; exit 0 ;;
            --) shift; FORWARD=("$@"); break ;;
            *) die "unknown argument: $1 (put installer flags after --)" ;;
        esac
        shift
    done
    $CONDADIR_SET || { usage; die "-d/--dir is required"; }

    local script_dir base env_dir conda_sh installer
    script_dir="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
    installer="${script_dir}/create_conda_environment.sh"
    base="${CONDADIR}/miniforge3"
    env_dir="${base}/envs/${CONDA_ENV_NAME}"
    conda_sh="${base}/etc/profile.d/conda.sh"

    # ---- 1. install (timed) ----
    local install_secs=0
    if ! $VALIDATE_ONLY; then
        [[ -f "$installer" ]] || die "installer not found: $installer"
        info "Running installer: $installer -d $CONDADIR -n $CONDA_ENV_NAME ${FORWARD[*]}"
        SECONDS=0
        bash "$installer" -d "$CONDADIR" -n "$CONDA_ENV_NAME" "${FORWARD[@]}" \
            || die "installer failed"
        install_secs=$SECONDS
        info "Install completed in ${install_secs}s."
    fi

    # ---- 2. activate ----
    [[ -f "$conda_sh" ]] || die "conda not found at ${base} (did the install run?)"
    # shellcheck source=/dev/null
    source "$conda_sh" || die "cannot source ${conda_sh}"
    [[ -d "$env_dir" ]] || die "environment '${CONDA_ENV_NAME}' not found at ${env_dir}"
    conda activate "$CONDA_ENV_NAME" || die "cannot activate ${CONDA_ENV_NAME}"

    SECONDS=0
    echo
    echo "==================== VALIDATION ===================="
    check 0 "environment '${CONDA_ENV_NAME}' activates ($(python --version 2>&1))"

    # ---- 3. GPU visibility ----
    local expect_gpu=0
    if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
        expect_gpu=1
        local ceil
        ceil=$(nvidia-smi 2>/dev/null | sed -n 's/.*CUDA Version:[[:space:]]*\([0-9.]*\).*/\1/p' | head -1)
        info "GPU present; driver CUDA ceiling: ${ceil:-unknown}"
    else
        warn "No NVIDIA GPU detected — running CPU-only validation (framework GPU checks will be informational)."
    fi

    # ---- 4. single CUDA stack ----
    local conda_torch pip_nvidia conda_cuda
    conda_torch=$(conda list 2>/dev/null | grep -cE '^pytorch[[:space:]]')
    pip_nvidia=$(pip list 2>/dev/null | grep -icE '^nvidia-[a-z0-9-]*-cu[0-9]+')
    conda_cuda=$(conda list 2>/dev/null \
        | grep -iE '^(cudatoolkit|cuda-toolkit|cudnn|cuda-version|libcublas|libcudnn|nccl)[[:space:]]' || true)

    if [[ "$conda_torch" -gt 0 ]]; then
        info "CUDA mode: conda (PyTorch from conda-forge)."
        # conda CUDA deps are expected here; a stray pip CUDA stack is the fault.
        check "$([[ "$pip_nvidia" -eq 0 ]] && echo 0 || echo 1)" \
            "no rogue pip nvidia-*-cu* wheels alongside conda PyTorch (found: ${pip_nvidia})"
    elif [[ "$pip_nvidia" -gt 0 ]]; then
        info "CUDA mode: pip (framework wheels provide CUDA)."
        # conda layer must contribute no CUDA.
        if [[ -n "$conda_cuda" ]]; then
            echo "$conda_cuda" | sed 's/^/      /'
            check 1 "conda layer is CUDA-free (mixed conda+pip CUDA is a resolution hazard)"
        else
            check 0 "conda layer is CUDA-free"
        fi
        # exactly one CUDA major across the pip wheels.
        local majors nmaj
        majors=$(pip list 2>/dev/null | grep -iE '^nvidia-[a-z0-9-]*-cu[0-9]+' \
            | grep -oE 'cu[0-9]+' | sort -u)
        nmaj=$(printf '%s\n' "$majors" | grep -c .)
        check "$([[ "$nmaj" -le 1 ]] && echo 0 || echo 1)" \
            "single CUDA major across pip wheels ($(echo $majors | tr '\n' ' '))"
    else
        info "No CUDA stack present (CPU-only or no DL frameworks)."
    fi

    # ---- 5. framework functional tests ----
    EXPECT_GPU="$expect_gpu" python - <<'PY'
import os, sys
expect_gpu = os.environ.get("EXPECT_GPU") == "1"
failures = 0

def report(name, ok, detail):
    global failures
    tag = "PASS" if ok else "FAIL"
    if not ok:
        failures += 1
    print(f"  {tag}  {name}: {detail}")

# ---- PyTorch ----
try:
    import torch
    avail = torch.cuda.is_available()
    if avail:
        x = torch.randn(2048, 2048, device="cuda")
        _ = (x @ x).sum().item()
        torch.cuda.synchronize()
        detail = (f"cuda_build={torch.version.cuda} cudnn={torch.backends.cudnn.version()} "
                  f"device={torch.cuda.get_device_name(0)} matmul=ok")
    else:
        detail = f"cuda_build={torch.version.cuda} cuda.is_available()=False"
    report("torch", (avail or not expect_gpu), detail)
except ModuleNotFoundError:
    pass
except Exception as e:
    report("torch", False, f"{type(e).__name__}: {e}")

# ---- TensorFlow ----
try:
    import tensorflow as tf
    gpus = tf.config.list_physical_devices("GPU")
    if gpus:
        with tf.device("/GPU:0"):
            a = tf.random.normal((2048, 2048))
            _ = tf.reduce_sum(tf.linalg.matmul(a, a)).numpy()
        detail = f"gpus={len(gpus)} matmul=ok"
    else:
        detail = "no GPU devices visible"
    report("tensorflow", (bool(gpus) or not expect_gpu), f"{tf.__version__}: {detail}")
except ModuleNotFoundError:
    pass
except Exception as e:
    report("tensorflow", False, f"{type(e).__name__}: {e}")

# ---- JAX ----
try:
    import jax, jax.numpy as jnp
    devs = jax.devices()
    plats = {d.platform for d in devs}
    on_gpu = any(p in ("gpu", "cuda", "rocm") for p in plats)
    if on_gpu:
        a = jnp.ones((2048, 2048))
        _ = float(jnp.dot(a, a).sum())
        detail = f"devices={plats} dot=ok"
    else:
        detail = f"devices={plats} (CPU)"
    report("jax", (on_gpu or not expect_gpu), f"{jax.__version__}: {detail}")
except ModuleNotFoundError:
    pass
except Exception as e:
    report("jax", False, f"{type(e).__name__}: {e}")

sys.exit(1 if failures else 0)
PY
    check $? "deep-learning frameworks use the GPU (or none installed / CPU-only)"

    # ---- 6. import sanity for other groups (non-fatal) ----
    echo "  -- optional package imports (informational) --"
    local mod
    for mod in numpy scipy pandas h5py uproot awkward vector ROOT rucio gfal2; do
        if python -c "import ${mod}" >/dev/null 2>&1; then
            echo "     ok: ${mod}"
        fi
    done
    for bin in rclone globus rucio; do
        command -v "$bin" >/dev/null 2>&1 && echo "     ok: ${bin} (cli)"
    done

    local validate_secs=$SECONDS

    # ---- 7. storage & summary ----
    local env_size base_size
    env_size=$(du -sh "$env_dir" 2>/dev/null | cut -f1)
    base_size=$(du -sh "$base" 2>/dev/null | cut -f1)

    echo
    echo "==================== SUMMARY ===================="
    echo "  Environment : ${CONDA_ENV_NAME}"
    $VALIDATE_ONLY || echo "  Install time: ${install_secs}s"
    echo "  Validate time: ${validate_secs}s"
    $VALIDATE_ONLY || echo "  Total time  : $((install_secs + validate_secs))s"
    echo "  Env storage : ${env_size:-?}  (${env_dir})"
    echo "  Base storage: ${base_size:-?}  (${base})"
    echo "  Checks      : ${PASS} passed, ${FAIL} failed"
    echo "================================================"

    [[ "$FAIL" -eq 0 ]] || exit 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
