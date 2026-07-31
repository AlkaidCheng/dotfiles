#!/usr/bin/env bash
# check_hep_env.sh — read-only diagnostics for a conda-based HEP software stack.
#
# Validates the wiring an environment built by
# environment/create_conda_environment.sh relies on, and prints everything
# needed to debug it when it drifts:
#   * active environment, compilers, and key tools on PATH
#   * MadGraph: install root, version, the configuration chain (per-user vs
#     install config) with lint for the common traps -- values whose paths do
#     not exist, lines "disabled" with a trailing '#' (MG still parses them),
#     user-config lines shadowing the shared config -- plus effective options,
#     the make_opts -lstdc++ patch, and the pre-compiled model cache
#   * LHAPDF: prefix/version, data-path search order, set index, installed
#     PDF sets, python bindings
#   * Pythia8 + MG5aMC_PY8_interface: versions, executable, dynamic-linkage
#     check (every Pythia8/HepMC/LHAPDF dependency should resolve into the
#     active environment), and the version stamps written at build time
#
# Read-only: never modifies configuration or installs anything.
#
# Usage:
#   check_hep_env.sh              # full report (invokes mg5_aMC once)
#   check_hep_env.sh --fast       # skip the mg5_aMC invocation
#   check_hep_env.sh --ascii      # plain ASCII tags instead of unicode glyphs
#   check_hep_env.sh MG5_ROOT     # override MadGraph root autodetection
#
# Colors and glyphs auto-disable when output is piped, when the locale is not
# UTF-8, or when NO_COLOR is set (https://no-color.org).
#
# Exit code: 0 all checks pass, 1 warnings only, 2 at least one failure.

set -o pipefail

FAST=false
ASCII=false
MG5_ROOT_OVERRIDE=""
for arg in "$@"; do
    case "$arg" in
        --fast)    FAST=true ;;
        --ascii)   ASCII=true ;;
        -h|--help) sed -n '2,/^# Exit code/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)         MG5_ROOT_OVERRIDE="$arg" ;;
    esac
done

# --------------------------------------------------------------------------- #
# Reporting helpers
# --------------------------------------------------------------------------- #
# Rich display (colors + unicode glyphs) on an interactive UTF-8 terminal;
# plain grep-able ASCII tags when piped, with --ascii, or under NO_COLOR.
USE_COLOR=true; USE_GLYPHS=true
{ [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; } || USE_COLOR=false
[[ -t 1 ]] || USE_GLYPHS=false
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
    *[Uu][Tt][Ff]-8* | *[Uu][Tt][Ff]8*) : ;;
    *) USE_GLYPHS=false ;;
esac
$ASCII && USE_GLYPHS=false

if $USE_COLOR; then
    C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_FAIL=$'\033[31m'
    C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'; C_HDR=$'\033[1;36m'; C_OFF=$'\033[0m'
else
    C_OK=""; C_WARN=""; C_FAIL=""; C_BOLD=""; C_DIM=""; C_HDR=""; C_OFF=""
fi
if $USE_GLYPHS; then
    S_OK="✓"; S_WARN="⚠"; S_FAIL="✗"
else
    S_OK="[ OK ]"; S_WARN="[WARN]"; S_FAIL="[FAIL]"
fi
N_OK=0; N_WARN=0; N_FAIL=0

section() {
    local title="$1" pad n
    if $USE_GLYPHS; then
        n=$(( 54 - ${#title} )); [[ $n -lt 4 ]] && n=4
        printf -v pad '%*s' "$n" ''
        printf '\n%s── %s %s%s\n' "$C_HDR" "$title" "${pad// /─}" "$C_OFF"
    else
        printf '\n%s== %s ==%s\n' "$C_BOLD" "$title" "$C_OFF"
    fi
}
kv()   { printf '  %s%-26s%s %s\n' "$C_DIM" "$1" "$C_OFF" "$2"; }
ok()   { printf '  %s%s%s %s\n' "$C_OK"   "$S_OK"   "$C_OFF" "$*"; N_OK=$((N_OK+1)); }
warn() { printf '  %s%s%s %s\n' "$C_WARN" "$S_WARN" "$C_OFF" "$*"; N_WARN=$((N_WARN+1)); }
fail() { printf '  %s%s%s %s\n' "$C_FAIL" "$S_FAIL" "$C_OFF" "$*"; N_FAIL=$((N_FAIL+1)); }

# Portable realpath (macOS readlink may lack -f).
resolve() {
    if readlink -f / >/dev/null 2>&1; then
        readlink -f "$1"
    else
        python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$1"
    fi
}

# --------------------------------------------------------------------------- #
# Header
# --------------------------------------------------------------------------- #
printf '%sHEP environment diagnostics%s\n' "$C_BOLD" "$C_OFF"
printf '%s  env: %s | host: %s | %s%s\n' "$C_DIM" \
    "${CONDA_DEFAULT_ENV:-none}" "$(hostname -s 2>/dev/null || hostname)" \
    "$(date '+%Y-%m-%d %H:%M')" "$C_OFF"

# --------------------------------------------------------------------------- #
# Environment
# --------------------------------------------------------------------------- #
section "Environment"
if [[ -n "${CONDA_PREFIX:-}" ]]; then
    ok "conda environment active: ${CONDA_DEFAULT_ENV:-?} (${CONDA_PREFIX})"
else
    fail "no conda environment active -- activate it first, then re-run"
fi
kv "python3" "$(command -v python3 || echo MISSING)  $(python3 --version 2>/dev/null)"
kv "CC / CXX / FC" "${CC:-unset} / ${CXX:-unset} / ${FC:-unset}"
if [[ -n "${CONDA_PREFIX:-}" && -n "${CXX:-}" ]]; then
    cxx_path=$(command -v "$CXX" 2>/dev/null)
    if [[ -n "$cxx_path" && "$cxx_path" != "$CONDA_PREFIX"* ]]; then
        warn "CXX resolves outside the environment ($cxx_path); builds may mix toolchains"
    fi
fi

# --------------------------------------------------------------------------- #
# Tool inventory
# --------------------------------------------------------------------------- #
section "Tool inventory"
for t in mg5_aMC lhapdf-config lhapdf pythia8-config; do
    p=$(command -v "$t" 2>/dev/null)
    if [[ -n "$p" ]]; then kv "$t" "$p"; else warn "$t: MISSING from PATH"; fi
done
for t in gnuplot root gfortran; do
    p=$(command -v "$t" 2>/dev/null)
    kv "$t" "${p:-not found (optional)}"
done
if [[ -n "${CONDA_PREFIX:-}" ]]; then
    if [[ -f "${CONDA_PREFIX}/include/HepMC/IO_BaseClass.h" ]]; then
        ok "HepMC2 headers present in the environment"
    else
        warn "HepMC2 headers missing (conda package 'hepmc2'); the PY8 interface cannot be (re)built"
    fi
fi

# --------------------------------------------------------------------------- #
# MadGraph install + configuration chain
# --------------------------------------------------------------------------- #
MG5_BIN=$(command -v mg5_aMC 2>/dev/null)
MG5_ROOT="$MG5_ROOT_OVERRIDE"
if [[ -z "$MG5_ROOT" && -n "$MG5_BIN" ]]; then
    MG5_ROOT=$(resolve "$MG5_BIN"); MG5_ROOT=${MG5_ROOT%/bin/mg5_aMC}
fi

section "MadGraph"
if [[ -z "$MG5_ROOT" || ! -d "$MG5_ROOT" ]]; then
    warn "MadGraph root not found (no mg5_aMC on PATH and no override given); skipping MG checks"
else
    kv "root" "$MG5_ROOT"
    kv "version" "$(sed -n 's/^ *version *= *//p' "$MG5_ROOT/VERSION" 2>/dev/null | head -1)"

    # Configuration chain, highest priority first (MG merges first-read-wins).
    USER_CFG=""
    for c in "$HOME/.config/mg5_configuration.txt" "$HOME/.mg5/mg5_configuration.txt"; do
        [[ -f "$c" ]] && { USER_CFG="$c"; break; }
    done
    INSTALL_CFG="$MG5_ROOT/input/mg5_configuration.txt"
    kv "user config" "${USER_CFG:-none}"
    kv "install config" "$([[ -f "$INSTALL_CFG" ]] && echo "$INSTALL_CFG" || echo MISSING)"

    # Lint one key in one config file. Prints every ACTIVE line and flags:
    # trailing-'#' pseudo-comments (MG still parses the line), values whose
    # paths do not exist, duplicate active definitions.
    # Sets LINT_VALUE to the last active (cleaned) value found.
    LINT_VALUE=""
    lint_cfg_key() {
        local file="$1" key="$2" tag="$3" want="$4"   # want: file|dir|(empty)
        LINT_VALUE=""
        [[ -f "$file" ]] || return 0
        local matches; matches=$(grep -n "^[[:space:]]*${key}[[:space:]]*=" "$file" 2>/dev/null)
        [[ -z "$matches" ]] && return 0
        local count=0 line lineno raw clean
        while IFS= read -r line; do
            count=$((count+1))
            lineno=${line%%:*}
            raw=${line#*:}; raw=${raw#*=}
            clean=${raw%%#*}
            clean=$(printf '%s' "$clean" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
            kv "$key ($tag:$lineno)" "$clean"
            if [[ "$raw" == *"#"* ]]; then
                warn "$key in $tag has a trailing '#': MG treats the line as ACTIVE (disable with a leading '#')"
            fi
            local path="$clean"
            [[ "$path" == ./* ]] && path="$MG5_ROOT/${path#./}"
            if [[ -n "$want" && -n "$path" ]]; then
                if [[ "$want" == file && ! -f "$path" ]] || [[ "$want" == dir && ! -d "$path" ]]; then
                    fail "$key in $tag points to a non-existent $want: $path"
                fi
            fi
            LINT_VALUE="$clean"
        done <<< "$matches"
        [[ $count -gt 1 ]] && warn "$key defined $count times in $tag (last one wins within a file)"
        return 0
    }

    for spec in "lhapdf:file" "lhapdf_py2:file" "lhapdf_py3:file" \
                "pythia8_path:dir" "mg5amc_py8_interface_path:dir" "auto_update:"; do
        key=${spec%%:*}; want=${spec#*:}
        lint_cfg_key "$USER_CFG"    "$key" "user"    "$want"; user_val="$LINT_VALUE"
        lint_cfg_key "$INSTALL_CFG" "$key" "install" "$want"; inst_val="$LINT_VALUE"
        if [[ -n "$user_val" && -n "$inst_val" && "$user_val" != "$inst_val" ]]; then
            warn "$key: user config shadows the install config (user wins: $user_val)"
        fi
        # Remember the effective value for later sections (user wins).
        eval "CFG_${key}=\"\${user_val:-\$inst_val}\""
    done

    # make_opts template patch (needed to link conda's shared-only LHAPDF).
    MKOPTS="$MG5_ROOT/Template/LO/Source/make_opts"
    if [[ -f "$MKOPTS" ]]; then
        if grep -q 'llhapdf += -lstdc++' "$MKOPTS"; then
            ok "make_opts template carries the -lstdc++ LHAPDF link fix"
        else
            warn "make_opts template lacks 'llhapdf += -lstdc++'; lhapdf-mode builds will fail at the gensym link"
        fi
    fi

    # Pre-compiled default model cache (required on read-only shared installs).
    if compgen -G "$MG5_ROOT/models/sm/"*.pkl >/dev/null 2>&1; then
        ok "default model cache present (models/sm/*.pkl)"
    else
        warn "default model cache missing; first use tries to write into $MG5_ROOT/models/sm"
    fi

    # Effective options as MG itself resolves them (slow path).
    if ! $FAST && [[ -n "$MG5_BIN" ]]; then
        section "MadGraph effective options (display options)"
        MG5_OUT=$(printf 'display options\nexit\n' | mg5_aMC 2>&1)
        echo "$MG5_OUT" | grep -iE "^\s+(lhapdf|lhapdf_py2|lhapdf_py3|pythia8_path|mg5amc_py8_interface_path|auto_update)\s+:" \
            | sed 's/^[[:space:]]*/  /'
        while IFS= read -r bad; do
            [[ -n "$bad" ]] && warn "MG startup: $bad"
        done <<< "$(echo "$MG5_OUT" | grep "does not seem to correspond" )"
    fi
fi

# --------------------------------------------------------------------------- #
# LHAPDF
# --------------------------------------------------------------------------- #
section "LHAPDF"
if command -v lhapdf-config >/dev/null 2>&1; then
    kv "version / prefix" "$(lhapdf-config --version 2>/dev/null) / $(lhapdf-config --prefix 2>/dev/null)"
    kv "datadir" "$(lhapdf-config --datadir 2>/dev/null)"
    kv "LHAPDF_DATA_PATH" "${LHAPDF_DATA_PATH:-unset}"

    # Every directory on the effective search path: index + set count.
    SEARCH="${LHAPDF_DATA_PATH:+${LHAPDF_DATA_PATH}:}$(lhapdf-config --datadir 2>/dev/null)"
    seen=""
    IFS=':' read -ra parts <<< "$SEARCH"
    for d in "${parts[@]}"; do
        [[ -z "$d" || "$seen" == *"|$d|"* ]] && continue
        seen="$seen|$d|"
        if [[ ! -d "$d" ]]; then kv "search dir" "$d (missing)"; continue; fi
        nsets=$(find "$d" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
        idx="no index"; [[ -f "$d/pdfsets.index" ]] && idx="pdfsets.index ok"
        kv "search dir" "$d ($nsets sets, $idx)"
    done
    if python3 -c 'import lhapdf' 2>/dev/null; then
        ok "python bindings import; search path: $(python3 -c 'import lhapdf; print(lhapdf.paths())' 2>/dev/null)"
    else
        warn "python bindings (import lhapdf) not importable in this environment"
    fi
else
    warn "lhapdf-config missing; skipping LHAPDF checks"
fi

# --------------------------------------------------------------------------- #
# Pythia8 + MG5aMC_PY8_interface
# --------------------------------------------------------------------------- #
section "Pythia8 + PY8 interface"
PY8_VER=""
if command -v pythia8-config >/dev/null 2>&1; then
    PY8_VER=$(pythia8-config --version 2>/dev/null)
    kv "pythia8" "$PY8_VER  ($(pythia8-config --prefix 2>/dev/null))"
else
    warn "pythia8-config missing; skipping Pythia8 checks"
fi

IFPATH="${CFG_mg5amc_py8_interface_path:-}"
[[ "$IFPATH" == ./* && -n "$MG5_ROOT" ]] && IFPATH="$MG5_ROOT/${IFPATH#./}"
if [[ -z "$IFPATH" ]]; then
    warn "mg5amc_py8_interface_path not configured; shower=Pythia8 unavailable in MadEvent"
elif [[ ! -x "$IFPATH/MG5aMC_PY8_interface" ]]; then
    fail "interface executable missing at $IFPATH"
else
    ok "interface executable: $IFPATH/MG5aMC_PY8_interface"

    # Version stamps written at build time.
    if [[ -f "$IFPATH/PYTHIA8_VERSION_ON_INSTALL" ]]; then
        built=$(cat "$IFPATH/PYTHIA8_VERSION_ON_INSTALL")
        if [[ -n "$PY8_VER" && "$built" != "$PY8_VER" ]]; then
            warn "interface built against Pythia8 $built but environment has $PY8_VER -- rebuild it"
        else
            ok "interface Pythia8 stamp matches the environment ($built)"
        fi
    else
        kv "version stamp" "none (PYTHIA8_VERSION_ON_INSTALL missing)"
    fi

    # Dynamic linkage: every pythia/hepmc/lhapdf dependency should resolve
    # into the active environment -- not a private tool build, not 'not found'.
    if command -v ldd >/dev/null 2>&1; then
        LINKS=$(ldd "$IFPATH/MG5aMC_PY8_interface" 2>/dev/null | grep -iE 'pythia|hepmc|lhapdf')
        echo "$LINKS" | sed 's/^[[:space:]]*/    /'
        if echo "$LINKS" | grep -q "not found"; then
            fail "interface has unresolved libraries"
        elif [[ -n "${CONDA_PREFIX:-}" ]] && echo "$LINKS" | grep -v "$CONDA_PREFIX" | grep -q "=>"; then
            warn "interface links libraries from outside the environment (stale build against another stack?)"
        elif [[ -n "$LINKS" ]]; then
            ok "interface links Pythia8/HepMC from the active environment"
        fi
    else
        kv "linkage check" "skipped (no ldd on this platform)"
    fi
fi

# --------------------------------------------------------------------------- #
# Activation hooks
# --------------------------------------------------------------------------- #
if [[ -n "${CONDA_PREFIX:-}" && -d "${CONDA_PREFIX}/etc/conda/activate.d" ]]; then
    section "Activation hooks"
    for h in "${CONDA_PREFIX}/etc/conda/activate.d/"*.sh; do
        [[ -f "$h" ]] && kv "hook" "$h"
    done
fi

# --------------------------------------------------------------------------- #
# Summary
# --------------------------------------------------------------------------- #
section "Summary"
printf '  %s%s %d passed%s   %s%s %d warnings%s   %s%s %d failures%s\n' \
    "$C_OK" "$S_OK" "$N_OK" "$C_OFF" \
    "$C_WARN" "$S_WARN" "$N_WARN" "$C_OFF" \
    "$C_FAIL" "$S_FAIL" "$N_FAIL" "$C_OFF"
if [[ $N_FAIL -gt 0 ]]; then
    printf '  %sverdict: issues found that will break usage%s\n' "$C_FAIL" "$C_OFF"
    exit 2
elif [[ $N_WARN -gt 0 ]]; then
    printf '  %sverdict: functional, but review the warnings%s\n' "$C_WARN" "$C_OFF"
    exit 1
else
    printf '  %sverdict: all checks passed%s\n' "$C_OK" "$C_OFF"
    exit 0
fi
