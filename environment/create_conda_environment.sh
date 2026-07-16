#!/bin/bash
#
# create_conda_environment.sh
#
# Bootstrap a Miniforge (conda-forge) base and build a scientific Python
# environment from it. Everything is installed from conda-forge with strict
# channel priority; GPU-heavy deep-learning frameworks are handled so that a
# single environment ends up with exactly one, consistent CUDA stack.
#
# Supported platforms: Linux and macOS (Intel/Apple Silicon). WSL works as
# Linux. Native Windows (Git Bash/MSYS) is not supported -- run under WSL.
#
# Resolution strategy (order matters for a clean solve):
#   1. ROOT first          -- heaviest constraints, pins a compatible base
#   2. one combined solve  -- base sci stack + requested conda package groups
#   3. conda PyTorch        -- only when PyTorch is the *sole* DL framework
#   4. pip last             -- multi-framework DL group + pip-only extras
#
# CUDA policy:
#   * PyTorch alone            -> conda-forge pytorch-gpu / pytorch-cpu
#                                 (auto-selected via the NVIDIA driver).
#   * PyTorch + TF and/or JAX  -> all frameworks via pip, installed last and
#     (or TF/JAX without torch)   together so they share one nvidia-*-cu12 set.
#   The two modes never mix, so there is only ever a single CUDA provider.

set -o pipefail

# --------------------------------------------------------------------------- #
# Defaults
# --------------------------------------------------------------------------- #
CONDA_ENV_NAME="envbase"
CONDA_PYTHON_VERSION="3.12"
ROOT_INSTALL_VERSION="latest"
CUDA_OVERRIDE="auto"           # auto | 12 | 13 | cpu

CONDADIR=""
CONDADIR_SET=false

INSTALL_ROOT=false
INSTALL_HEP=false
INSTALL_MLBASE=false
INSTALL_ALKAID=false
INSTALL_PYTORCH=false
INSTALL_TENSORFLOW=false
INSTALL_JAX=false
INSTALL_TRANSFER=false
INSTALL_ATLAS=false
INSTALL_WORKFLOW=false

MINIFORGE_URL_BASE="https://github.com/conda-forge/miniforge/releases/latest/download"

# PyTorch pip wheel index tags per CUDA major, newest-first. Probed against the
# live index before use, so a retired tag degrades gracefully. Bump as PyTorch
# publishes new builds.
TORCH_CU12_TAGS=(cu129 cu128 cu126)
TORCH_CU13_TAGS=(cu130)

# MadGraph5_aMC@NLO is installed from the official tarball (not conda) so it does
# not pin the environment's Python; current releases support Python 3.12+.
# Override the version with --mg5ver.
MG5_VERSION="3.7.2"

# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #
die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "INFO: $*"; }
warn() { echo "WARNING: $*" >&2; }

# Echo a command, run it, and abort with a clear message on failure.
run() {
    echo "+ $*"
    "$@" || die "command failed: $*"
}

usage() {
    cat <<EOF
Usage: $0 -d DIR [options]

Bootstrap Miniforge and build a conda-forge scientific Python environment.

Required:
  -d, --dir DIR       Directory to install Miniforge and its environments

Environment:
  -n, --name NAME     Conda environment name (default: $CONDA_ENV_NAME)
  -p, --python VER    Python version (default: $CONDA_PYTHON_VERSION)

Package groups (opt-in):
  -r, --root          ROOT + HEP python ecosystem (uproot, awkward, vector, hist, mplhep)
      --rootver VER   ROOT version (default: $ROOT_INSTALL_VERSION; only with -r)
      --hep           HEP generators (delphes, pythia8, fastjet; madgraph from source)
      --mg5ver VER    MadGraph version to install (default: $MG5_VERSION; only with --hep)
  -m, --mlbase        Classical ML stack (scikit-learn, xgboost, ray, ...)
      --transfer      File-transfer tools (rclone, globus-cli, openssh)
      --atlas         ATLAS grid tools (rucio-clients, gfal2 family)
  -w, --workflow      Workflow tools (law)
      --alkaid        Alkaid's personal packages

Deep-learning frameworks (GPU-aware):
      --pytorch       PyTorch
      --tensorflow    TensorFlow
      --jax           JAX
      --dl            Shortcut for --pytorch --tensorflow --jax (coexisting)

GPU / CUDA:
      --cuda VALUE    Force the CUDA target for the pip DL path: 12 | 13 | cpu
                      (default: auto-detect from the NVIDIA driver)

Other:
  -h, --help          Show this help and exit
EOF
}

# Guard the platform. WSL reports as Linux and is fine; only native Windows
# (Git Bash / MSYS / Cygwin) needs to be rejected with an actionable message.
detect_platform() {
    case "$OSTYPE" in
        linux*|darwin*) return 0 ;;
        msys*|cygwin*)
            die "Native Windows (Git Bash/MSYS) is not supported. Run this inside WSL, where it works unchanged as Linux." ;;
    esac
    case "$(uname -s)" in
        Linux|Darwin) return 0 ;;
        MINGW*|MSYS*|CYGWIN*)
            die "Native Windows (Git Bash/MSYS) is not supported. Run this inside WSL, where it works unchanged as Linux." ;;
        *) die "Unsupported operating system: $OSTYPE / $(uname -s)" ;;
    esac
}

# Download URL -> destination, preferring curl then wget.
download() {
    local url="$1" dest="$2" tmp="${2}.part"
    rm -f "$tmp"
    if command -v curl >/dev/null 2>&1; then
        curl -fL -o "$tmp" "$url" || { rm -f "$tmp"; return 1; }
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$tmp" "$url" || { rm -f "$tmp"; return 1; }
    else
        die "Neither curl nor wget is installed; cannot download $url"
    fi
    # Expose the final path only once the download fully succeeded.
    mv -f "$tmp" "$dest"
}

# Ensure a Miniforge base exists at $1 (idempotent).
install_miniforge() {
    local prefix="$1"
    local stamp="${prefix}/.install_complete"

    if [[ -f "$stamp" ]]; then
        info "conda already installed at ${prefix}"
        return 0
    fi
    if [[ -f "${prefix}/etc/profile.d/conda.sh" ]]; then
        # a complete install predating stamps -- adopt it
        info "conda already installed at ${prefix}"
        touch "$stamp"
        return 0
    fi
    if [[ -d "$prefix" ]]; then
        warn "Clearing incomplete Miniforge install at ${prefix}"
        rm -rf "$prefix"
    fi

    mkdir -p "$CONDADIR" || die "cannot create ${CONDADIR}"

    local asset="Miniforge3-$(uname)-$(uname -m).sh"
    local url="${MINIFORGE_URL_BASE}/${asset}"
    local installer="${CONDADIR}/${asset}"

    if [[ ! -f "$installer" ]]; then
        info "Downloading Miniforge installer: ${asset}"
        download "$url" "$installer" || die "failed to download ${url}"
    else
        info "Miniforge installer already present: ${asset}"
    fi

    info "Installing Miniforge to ${prefix}"
    bash "$installer" -b -p "$prefix" || die "Miniforge installation failed"

    # Remove the installer artifact now that the base is installed.
    rm -f "$installer"

    touch "$stamp"
}

configure_conda() {
    info "Configuring conda (strict channel priority, libmamba solver)"
    conda config --set channel_priority strict
    conda config --set solver libmamba
}

# --------------------------------------------------------------------------- #
# GPU / CUDA detection
# --------------------------------------------------------------------------- #

# True if a usable NVIDIA GPU + driver is present.
has_nvidia_gpu() {
    command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1
}

# Echo the driver's maximum supported CUDA *major* (e.g. "12"), or nothing.
# This is the ceiling the driver can run -- not an installed toolkit.
driver_cuda_major() {
    has_nvidia_gpu || return 0
    nvidia-smi 2>/dev/null \
        | sed -n 's/.*CUDA Version:[[:space:]]*\([0-9][0-9]*\)\.[0-9].*/\1/p' \
        | head -1
}

# Echo a PyTorch pip index tag (e.g. "cu129") for a CUDA major, probing the
# live index so retired tags are skipped. Empty if none is available.
torch_index_tag() {
    local major="$1"
    local -a cands=()
    case "$major" in
        12) cands=("${TORCH_CU12_TAGS[@]}") ;;
        13) cands=("${TORCH_CU13_TAGS[@]}") ;;
        *)  return 0 ;;
    esac
    local t
    if command -v curl >/dev/null 2>&1; then
        for t in "${cands[@]}"; do
            if curl -sfI "https://download.pytorch.org/whl/${t}/" >/dev/null 2>&1; then
                echo "$t"; return 0
            fi
        done
        return 0   # none of the candidates are served
    fi
    echo "${cands[0]}"   # cannot probe (no curl) -- assume newest known
}

# Decide the single CUDA major shared by the pip DL group. Echoes "12", "13"
# or "cpu". Honours --cuda; otherwise derives it from the driver ceiling
# intersected with what the *requested* frameworks support:
#   torch {11,12,13}, jax {12,13}, tf {12}.  Auto-selection is capped at 12
#   (the universally-supported major); 13 is opt-in via --cuda 13.
resolve_group_cuda_major() {
    case "$CUDA_OVERRIDE" in
        cpu) echo cpu; return 0 ;;
        12|13)
            if $INSTALL_TENSORFLOW && [[ "$CUDA_OVERRIDE" == 13 ]]; then
                die "TensorFlow has no CUDA 13 build; use --cuda 12 or drop --tensorflow."
            fi
            local cm; cm=$(driver_cuda_major)
            if [[ -n "$cm" && "$cm" -lt "$CUDA_OVERRIDE" ]]; then
                warn "Requested CUDA ${CUDA_OVERRIDE} exceeds the driver ceiling (${cm}.x); wheels may fail to run."
            fi
            echo "$CUDA_OVERRIDE"; return 0 ;;
    esac

    # --- auto ---
    local cm; cm=$(driver_cuda_major)
    if [[ -z "$cm" ]]; then
        echo cpu; return 0            # no GPU/driver -> CPU (expected, no warning)
    fi

    # Candidate majors, highest-first. 13 only when the driver allows it, no
    # TensorFlow is requested, and (if torch is requested) a cu13x wheel exists.
    local -a cand=()
    [[ "$cm" -ge 13 ]] && ! $INSTALL_TENSORFLOW && cand+=(13)
    [[ "$cm" -ge 12 ]] && cand+=(12)

    local m
    for m in "${cand[@]}"; do
        if $INSTALL_PYTORCH && [[ -z "$(torch_index_tag "$m")" ]]; then
            continue   # no usable torch wheel for this major
        fi
        echo "$m"; return 0
    done

    warn "NVIDIA driver supports only CUDA ${cm}.x, below what the requested frameworks need for GPU; falling back to CPU builds."
    echo cpu
}

# --------------------------------------------------------------------------- #
# Deep-learning installers
# --------------------------------------------------------------------------- #

# PyTorch as the sole DL framework: install from conda-forge so it stays part
# of the conda solve and shares the environment's stack (e.g. with ROOT).
install_conda_torch() {
    local -a pkgs=(torchvision torchaudio)
    case "$CUDA_OVERRIDE" in
        cpu)
            pkgs=(pytorch-cpu "${pkgs[@]}") ;;
        12|13)
            pkgs=(pytorch-gpu "${pkgs[@]}" "cuda-version=${CUDA_OVERRIDE}.*")
            if ! has_nvidia_gpu; then
                export CONDA_OVERRIDE_CUDA="${CUDA_OVERRIDE}.0"
                warn "No GPU detected; forcing CONDA_OVERRIDE_CUDA=${CONDA_OVERRIDE_CUDA} to build a GPU-capable env (e.g. from a login node)."
            fi ;;
        *)
            if has_nvidia_gpu; then
                pkgs=(pytorch-gpu "${pkgs[@]}")
                info "NVIDIA GPU detected -> installing the CUDA build of PyTorch."
            else
                pkgs=(pytorch-cpu "${pkgs[@]}")
                info "No NVIDIA GPU detected -> installing the CPU build of PyTorch."
            fi ;;
    esac
    run conda install -y -c conda-forge "${pkgs[@]}"
}

# Multiple DL frameworks (or TF/JAX alone): install via pip, last and together,
# so they all draw from one nvidia-*-cu12 wheel set.
install_pip_dl() {
    local major; major=$(resolve_group_cuda_major)
    info "Deep-learning (pip) CUDA target: ${major}"

    if $INSTALL_PYTORCH; then
        local tag="cpu"
        if [[ "$major" != cpu ]]; then
            tag=$(torch_index_tag "$major")
            [[ -z "$tag" ]] && { warn "No PyTorch CUDA ${major} wheel available; using the CPU build."; tag=cpu; }
        fi
        # --index-url replaces PyPI, so PyTorch must be its own command.
        run pip --cache-dir "$PIP_CACHE_DIR" install torch torchvision torchaudio \
            --index-url "https://download.pytorch.org/whl/${tag}"
    fi

    # TensorFlow + JAX resolve together from PyPI and reuse the wheels above.
    local -a extras=()
    if $INSTALL_TENSORFLOW; then
        [[ "$major" == cpu ]] && extras+=(tensorflow) || extras+=("tensorflow[and-cuda]")
    fi
    if $INSTALL_JAX; then
        [[ "$major" == cpu ]] && extras+=(jax) || extras+=("jax[cuda${major}]")
    fi
    if [[ ${#extras[@]} -gt 0 ]]; then
        run pip --cache-dir "$PIP_CACHE_DIR" install "${extras[@]}"
    fi
}

# Verify there is exactly one CUDA stack and the frameworks import cleanly.
verify_cuda_stack() {
    info "Verifying CUDA / library consistency"

    if [[ "$DL_MODE" == pip ]]; then
        local leaked
        leaked=$(conda list 2>/dev/null \
            | grep -iE '^(cudatoolkit|cuda-toolkit|cudnn|cuda-version|libcublas|libcudnn|nccl)[[:space:]]' \
            | awk '$NF != "pypi"' || true)
        if [[ -n "$leaked" ]]; then
            warn "conda-provided CUDA packages found alongside pip CUDA wheels -- this risks version-mismatch crashes:"
            echo "$leaked" >&2
            warn "Remove them (conda remove <pkg>) or recreate with pip-only CUDA."
        else
            info "  OK: conda layer is CUDA-free (single pip CUDA stack)."
        fi
        echo "  pip CUDA wheels:"
        pip list 2>/dev/null | grep -iE '^nvidia-[a-z-]*-cu[0-9]+' || echo "    (none)"
    fi

    # cap TF/JAX GPU-memory grabbing so the shared-process smoke test doesn't OOM.
    TF_FORCE_GPU_ALLOW_GROWTH=true XLA_PYTHON_CLIENT_PREALLOCATE=false \
        python - <<'PY' || warn "framework import smoke-test reported issues (see above)."
import importlib
for mod in ("torch", "tensorflow", "jax"):
    try:
        m = importlib.import_module(mod)
    except Exception:
        continue
    v = getattr(m, "__version__", "?")
    if mod == "torch":
        print(f"  torch {v}: cuda_build={m.version.cuda} available={m.cuda.is_available()}")
    elif mod == "tensorflow":
        try:
            n = len(m.config.list_physical_devices("GPU"))
        except Exception:
            n = "?"
        print(f"  tensorflow {v}: gpus={n}")
    elif mod == "jax":
        try:
            d = m.devices()[0].platform
        except Exception:
            d = "?"
        print(f"  jax {v}: default_device={d}")
PY
}

# Install MadGraph5_aMC@NLO from the official tarball (kept out of conda so it does
# not pin the environment's Python) and expose the launcher on the env PATH. MG5
# compiles Fortran on demand, hence the compilers added to the --hep conda group.
install_madgraph() {
    local dest="${CONDADIR}/madgraph"
    local src="${dest}/MG5_aMC_v${MG5_VERSION//./_}"

    local stamp="${src}/.install_complete"
    if [[ -f "$stamp" ]]; then
        info "MadGraph already installed at ${src}."
    elif [[ -x "${src}/bin/mg5_aMC" ]]; then
        # a complete install predating stamps -- adopt it
        info "MadGraph already installed at ${src}."
        touch "$stamp"
    else
        [[ -d "$src" ]] && { warn "Clearing incomplete MadGraph install at ${src}"; rm -rf "$src"; }
        mkdir -p "$dest"
        local tgz="${dest}/MG5_aMC_v${MG5_VERSION}.tar.gz"

        if [[ ! -f "$tgz" ]]; then
            # Launchpad groups files under a milestone folder that is usually
            # major.minor but occasionally the previous minor (e.g. 3.7.0 shipped
            # under 3.6.x). Try the likely folders and keep the first that
            # downloads (a real GET; HEAD probes get rate-limited/404 on Launchpad).
            local major="${MG5_VERSION%%.*}" minor
            minor="${MG5_VERSION#"${major}."}"; minor="${minor%%.*}"
            info "Downloading MadGraph ${MG5_VERSION}..."
            local ok=false s
            for s in "${major}.${minor}" "${major}.$((minor - 1))"; do
                if download "https://launchpad.net/mg5amcnlo/3.0/${s}.x/+download/MG5_aMC_v${MG5_VERSION}.tar.gz" "$tgz"; then
                    ok=true; break
                fi
            done
            $ok || die "Could not download MadGraph ${MG5_VERSION} from Launchpad; check --mg5ver."
        fi
        info "Extracting MadGraph to ${dest}..."
        # The MG5 tarball is packed on macOS and carries com.apple.* xattr pax
        # headers; GNU tar prints a harmless "Ignoring unknown extended header
        # keyword" line for each. Silence those on GNU tar (BSD tar lacks the
        # option and does not warn).
        local tar_opts=(-xzpf)
        tar --version 2>/dev/null | grep -q 'GNU tar' \
            && tar_opts=(--warning=no-unknown-keyword "${tar_opts[@]}")
        tar "${tar_opts[@]}" "$tgz" -C "$dest" || die "MadGraph extraction failed"
        touch "$stamp"
    fi

    # Expose the launcher on the active environment's PATH.
    ln -sf "${src}/bin/mg5_aMC" "${CONDA_PREFIX}/bin/mg5_aMC"
    info "MadGraph ${MG5_VERSION} available as 'mg5_aMC' (physics libs via its own 'install' command)."
}

# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #
main() {
    # ---- parse arguments ----
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -d|--dir)
                [[ -n "$2" && "${2:0:1}" != "-" ]] || { echo "ERROR: missing value for $1" >&2; usage; exit 1; }
                CONDADIR="$2"; CONDADIR_SET=true; shift ;;
            -n|--name)
                [[ -n "$2" && "${2:0:1}" != "-" ]] || { echo "ERROR: missing value for $1" >&2; usage; exit 1; }
                CONDA_ENV_NAME="$2"; shift ;;
            -p|--python)
                [[ -n "$2" && "${2:0:1}" != "-" ]] || { echo "ERROR: missing value for $1" >&2; usage; exit 1; }
                CONDA_PYTHON_VERSION="$2"; shift ;;
            -r|--root)       INSTALL_ROOT=true ;;
            --rootver)
                [[ -n "$2" && "${2:0:1}" != "-" ]] || { echo "ERROR: missing value for $1" >&2; usage; exit 1; }
                ROOT_INSTALL_VERSION="$2"; shift ;;
            --hep)           INSTALL_HEP=true ;;
            --mg5ver)
                [[ -n "$2" && "${2:0:1}" != "-" ]] || { echo "ERROR: missing value for $1" >&2; usage; exit 1; }
                MG5_VERSION="$2"; shift ;;
            -m|--mlbase)     INSTALL_MLBASE=true ;;
            --transfer)      INSTALL_TRANSFER=true ;;
            --atlas)         INSTALL_ATLAS=true ;;
            -w|--workflow)   INSTALL_WORKFLOW=true ;;
            --alkaid)        INSTALL_ALKAID=true ;;
            --pytorch)       INSTALL_PYTORCH=true ;;
            --tensorflow)    INSTALL_TENSORFLOW=true ;;
            --jax)           INSTALL_JAX=true ;;
            --dl)            INSTALL_PYTORCH=true; INSTALL_TENSORFLOW=true; INSTALL_JAX=true ;;
            --cuda)
                [[ -n "$2" && "${2:0:1}" != "-" ]] || { echo "ERROR: missing value for $1" >&2; usage; exit 1; }
                case "$2" in
                    auto|12|13|cpu) CUDA_OVERRIDE="$2" ;;
                    *) die "invalid --cuda value '$2' (expected: auto | 12 | 13 | cpu)" ;;
                esac
                shift ;;
            -h|--help)       usage; exit 0 ;;
            *) echo "ERROR: unknown option: $1" >&2; usage; exit 1 ;;
        esac
        shift
    done

    $CONDADIR_SET || { echo "ERROR: -d/--dir is required" >&2; usage; exit 1; }

    detect_platform

    # ---- deep-learning install mode ----
    # torch alone  -> conda; torch+others or tf/jax -> pip; else none.
    DL_MODE=none
    if $INSTALL_PYTORCH || $INSTALL_TENSORFLOW || $INSTALL_JAX; then
        if $INSTALL_PYTORCH && ! $INSTALL_TENSORFLOW && ! $INSTALL_JAX; then
            DL_MODE=conda-torch
        else
            DL_MODE=pip
        fi
    fi

    local conda_base="${CONDADIR}/miniforge3"

    # ---- base install & environment ----
    install_miniforge "$conda_base"
    # shellcheck source=/dev/null
    source "${conda_base}/etc/profile.d/conda.sh" || die "cannot source conda.sh"
    configure_conda

    local env_dir="${conda_base}/envs/${CONDA_ENV_NAME}"
    local env_stamp="${env_dir}/.install_complete"
    if [[ -f "$env_stamp" ]]; then
        info "Environment '${CONDA_ENV_NAME}' already exists; skipping creation."
    elif [[ -x "${env_dir}/bin/python" ]]; then
        # a complete env predating stamps -- adopt it
        info "Environment '${CONDA_ENV_NAME}' already exists; skipping creation."
        touch "$env_stamp"
    else
        [[ -d "$env_dir" ]] && { warn "Clearing incomplete environment at ${env_dir}"; rm -rf "$env_dir"; }
        run conda create -y -c conda-forge --name "$CONDA_ENV_NAME" python="$CONDA_PYTHON_VERSION"
        touch "$env_stamp"
    fi
    conda activate "$CONDA_ENV_NAME" || die "cannot activate ${CONDA_ENV_NAME}"

    PIP_CACHE_DIR="${CONDADIR}/.cache/pip"
    mkdir -p "$PIP_CACHE_DIR"

    # ---- stage A: ROOT first (heaviest constraints) ----
    if $INSTALL_ROOT; then
        if [[ "$ROOT_INSTALL_VERSION" == latest ]]; then
            run conda install -y -c conda-forge root
        else
            run conda install -y -c conda-forge "root==${ROOT_INSTALL_VERSION}"
        fi
    fi

    # ---- stage B: base scientific stack + requested conda groups, one solve ----
    local -a conda_pkgs=(
        numpy scipy pandas matplotlib h5py pyyaml
        pyarrow fsspec pytables sympy tqdm numba
        jupyterlab jupyterhub ruff click pytest
        pip twine gh glab
    )
    $INSTALL_ROOT     && conda_pkgs+=(uproot awkward vector hist mplhep)
    $INSTALL_HEP      && conda_pkgs+=(delphes pythia8 fortran-compiler cxx-compiler make meson ninja)
    $INSTALL_MLBASE   && conda_pkgs+=(scikit-learn scikit-optimize hyperopt)
    $INSTALL_TRANSFER && conda_pkgs+=(rclone globus-cli openssh)
    $INSTALL_ATLAS    && conda_pkgs+=(rucio-clients gfal2 gfal2-util python-gfal2)

    run conda install -y -c conda-forge "${conda_pkgs[@]}"

    # ---- stage C: PyTorch via conda (only when it is the sole DL framework) ----
    [[ "$DL_MODE" == conda-torch ]] && install_conda_torch

    # ---- stage D: pip (multi-framework DL group, then pip-only extras) ----
    [[ "$DL_MODE" == pip ]] && install_pip_dl

    if $INSTALL_HEP; then
        run pip --cache-dir "$PIP_CACHE_DIR" install fastjet
        install_madgraph
    fi

    if $INSTALL_MLBASE; then
        run pip --cache-dir "$PIP_CACHE_DIR" install xgboost nflows shapely "ray[tune]"
    fi

    if $INSTALL_WORKFLOW; then
        run pip --cache-dir "$PIP_CACHE_DIR" install law
    fi

    # jupyter extensions (not on conda-forge as a consistent set)
    run pip --cache-dir "$PIP_CACHE_DIR" install jupyterlab-nvdashboard jupyterlab-favorites

    if $INSTALL_ALKAID; then
        run pip --cache-dir "$PIP_CACHE_DIR" install quickstats aliad colstore
    fi

    pip --cache-dir "$PIP_CACHE_DIR" cache purge >/dev/null 2>&1 || true

    # ---- verify & clean ----
    [[ "$DL_MODE" != none ]] && verify_cuda_stack

    run conda clean -y --all
    info "Cleaned conda cache."

    echo
    info "Done. Environment '${CONDA_ENV_NAME}' is ready."
    info "Activate it with:"
    echo "    source ${conda_base}/etc/profile.d/conda.sh && conda activate ${CONDA_ENV_NAME}"
}

# Only run when executed directly, so the functions can be sourced for testing.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
