# dotfiles

Personal dotfiles and environment setup scripts.

## Contents

| Path | Description |
|------|-------------|
| `setup.sh` | Install shell convenience aliases |
| `scripts/` | Repository-management helper scripts (GitHub label setup, …) |
| `environment/` | Build scientific Python (conda) environments (+ VS Code / LCG helpers) |
| `diagnostics/` | Read-only health checks for the built environments |
| `ssh/` | SSH config and credential setup scripts for HPC facilities |

---

## Quick Start

```bash
git clone git@github.com:AlkaidCheng/dotfiles.git
cd dotfiles
source setup.sh
```

Sourcing `setup.sh` makes the scripts executable and defines the
`ssh-remote-*` aliases for the current session. Run it again in any
new session, or add `source /absolute/path/to/dotfiles/setup.sh` to
your own `.zshrc`/`.bashrc` if you want the aliases available
permanently.

---

## scripts/

Helper scripts for repository management.

### `setup_gh_labels.sh`

Applies a standard GitHub label set to one or more repositories, so every
project shares the same triage vocabulary. Managed labels are created or
updated in place, GitHub's unused default labels (`documentation`,
`question`) are removed, and custom labels are left untouched — re-running
is always safe.

Requires an authenticated [GitHub CLI](https://cli.github.com) (`gh`).

```bash
# current directory
./scripts/setup_gh_labels.sh

# one or more repo checkouts
./scripts/setup_gh_labels.sh path/to/repo1 path/to/repo2
```

The managed set:

| Group | Labels |
|-------|--------|
| Type (pick one) | `bug`, `feature`, `enhancement`, `perf`, `refactor`, `docs`, `design`, `test`, `benchmark`, `ci`, `deps`, `release`, `chore` |
| Modifier (stacks on a type) | `breaking` |
| Priority | `priority: critical` / `high` / `medium` / `low` |
| Status | `status: blocked` / `in progress` / `needs review` / `needs info` |
| Resolution | `wontfix`, `duplicate`, `invalid` |
| Community | `good first issue`, `help wanted` |

Distinctions the set encodes: `docs` is user-facing documentation while
`design` is proposals and architecture; `perf` is an optimization while
`benchmark` is the measurement harness; `ci` covers workflows while
`chore` is the remaining maintenance and tooling.

---

## environment/

Scripts for building and testing scientific Python environments, plus a
few development helpers (VS Code extension setup, LCG release listing).
The main entry point is `create_conda_environment.sh`.

### `create_conda_environment.sh`

Bootstraps a **Miniforge** (conda-forge) installation and builds a
scientific Python environment from it, with opt-in package groups for
ROOT, HEP generators, GPU-aware deep learning, ATLAS grid tools, and
more. Everything installs from conda-forge with strict channel priority,
and the deep-learning frameworks are arranged so a single environment
ends up with exactly one, consistent CUDA stack.

Runs on **Linux and macOS** (Apple Silicon or Intel); **WSL** works as
Linux. Native Windows (Git Bash/MSYS) is not supported — run it under WSL.

**Usage**

```bash
# minimal: a base scientific environment
./environment/create_conda_environment.sh -d ~/conda -n myenv

# with options
./environment/create_conda_environment.sh -d <install-dir> [-n NAME] [-p VER] [groups...]
```

`-d/--dir` (the directory where Miniforge and its environments live) is
the only required flag. Afterward, activate the environment with:

```bash
source <install-dir>/miniforge3/etc/profile.d/conda.sh && conda activate <name>
```

**Core options**

| Flag | Description |
|------|-------------|
| `-d, --dir DIR` | Directory to install Miniforge + environments (**required**) |
| `-n, --name NAME` | Environment name (default: `envbase`) |
| `-p, --python VER` | Python version (default: `3.12`) |
| `-h, --help` | Show help and exit |

The base environment always includes the core scientific stack (numpy,
scipy, pandas, matplotlib, h5py, pyarrow, pytables, sympy, numba, …),
JupyterLab/JupyterHub, `ruff`, `pytest`, and the `gh`/`glab` CLIs.

**Package groups** (opt-in, combinable)

| Flag | Adds |
|------|------|
| `-r, --root` | ROOT + HEP python ecosystem (uproot, awkward, vector, hist, mplhep) |
| `--rootver VER` | Pin the ROOT version (with `-r`; default: latest) |
| `--hep` | HEP generators + libs: delphes, pythia8, sherpa, evtgen, lhapdf, fastjet, hepmc2/3, rivet/yoda, and MadGraph (from source) |
| `--mg5ver VER` | Pin the MadGraph version (with `--hep`; default: 3.7.2) |
| `-m, --mlbase` | Classical ML: scikit-learn, scikit-optimize, hyperopt, xgboost, nflows, ray[tune], … |
| `--transfer` | File-transfer tools: rclone, globus-cli, openssh |
| `--atlas` | ATLAS grid tools: rucio-clients, gfal2 (+ bundled plugins) |
| `-w, --workflow` | Workflow tools: law |
| `--alkaid` | Personal packages: quickstats, aliad, colstore |

**Deep-learning frameworks** (GPU-aware, combinable)

| Flag | Description |
|------|-------------|
| `--pytorch` | PyTorch |
| `--tensorflow` | TensorFlow |
| `--jax` | JAX |
| `--dl` | Shortcut for all three, coexisting in one environment |
| `--cuda 12\|13\|cpu` | Force the CUDA target (default: auto-detect from the NVIDIA driver) |

How CUDA is handled:

- **PyTorch alone** installs from conda-forge (`pytorch-gpu`/`pytorch-cpu`,
  auto-selected from the driver).
- **PyTorch with TensorFlow and/or JAX** (or TF/JAX on their own) install
  from pip, together and last, so they share one `nvidia-*-cu12` wheel set.
- The CUDA major is derived from the NVIDIA driver, capped at what the
  requested frameworks support; override with `--cuda`.
- At the end the installer asserts that only one CUDA stack is present.

MadGraph is installed from the official tarball (not conda) so it does
not pin the environment's Python.

**Examples**

```bash
# ROOT analysis environment
./environment/create_conda_environment.sh -d ~/conda -n analysis -r

# GPU deep-learning environment with all three frameworks
./environment/create_conda_environment.sh -d ~/conda -n dl --dl

# HEP generators + ATLAS grid tools
./environment/create_conda_environment.sh -d ~/conda -n hep --hep --atlas
```

### `test_conda_environment.sh`

Acceptance test for `create_conda_environment.sh`, meant to run on a GPU
machine. It optionally runs the installer, then checks that the
environment activates, every installed deep-learning framework actually
uses the GPU, exactly one CUDA stack is present, and the requested
packages import — logging the total time and storage used.

```bash
# install a GPU environment, then validate + measure:
./environment/test_conda_environment.sh -d ~/conda -n gpuenv -- --dl --hep

# validate an environment that already exists (no reinstall):
./environment/test_conda_environment.sh -d ~/conda -n gpuenv --validate-only
```

Its own flags (`-d`, `-n`, `--validate-only`) come first; everything
after `--` is forwarded verbatim to `create_conda_environment.sh`.

---

## diagnostics/

Read-only health checks for the built environments.

### `check_hep_env.sh`

Validates the HEP-stack wiring an environment built with `--hep` relies on,
and prints everything needed to debug it when it drifts: tool paths,
MadGraph's configuration chain (with lint for values pointing at
non-existent paths, lines "disabled" with a trailing `#` that MadGraph
still parses, and per-user config lines shadowing the shared one), LHAPDF
data-path order and installed PDF sets, and the Pythia8 interface's
dynamic linkage and version stamps.

```bash
# with the environment activated:
diagnostics/check_hep_env.sh          # full report (invokes mg5_aMC once)
diagnostics/check_hep_env.sh --fast   # config-file checks only
```

Exit code: `0` all checks pass, `1` warnings only, `2` at least one failure.

---

## ssh/

Scripts for managing SSH configs and credentials across HPC facilities.
Currently supported: **CERN lxplus**, **NERSC (Perlmutter)**,
**LRC/Lawrencium (LBNL)**, and **S3DF (SLAC)**.

### Directory Layout

```
ssh/
├── config/
│   └── setup_ssh_configs.sh     Generate ~/.ssh/configs/<host>.conf drop-ins
│                                and register them in ~/.ssh/config via Include.
│                                Supports --lxplus, --nersc, --lrc, --s3df,
│                                or --all to apply one username to all hosts.
└── keys/
    ├── setup_ssh_key.sh         Master dispatcher: routes --host <name> to the
    │                            correct per-host script below. Hosts requiring
    │                            a username take -u <username>; those that prompt
    │                            interactively (lrc) do not.
    ├── setup_lxplus_key.sh      Obtains a Kerberos ticket via kinit (~25h).
    │                            Creates ~/.config/krb5.conf with CERN realm
    │                            settings on first run if not already present.
    ├── setup_nersc_key.sh       Obtains an sshproxy certificate (~24h).
    │                            Downloads the sshproxy binary on first run,
    │                            auto-detecting OS and architecture from the
    │                            NERSC portal.
    ├── setup_lrc_key.sh         Obtains an SSH certificate via request_cert.sh
    │                            (~12h). Clones lbnl-science-it/lrc-scripts on
    │                            first run; pulls updates on subsequent runs.
    ├── setup_s3df_key.sh        Generates an ed25519 key pair at ~/.ssh/s3df/key
    │                            and prints the public key for upload to the S3DF
    │                            key management portal.
    └── status_ssh_keys.sh       Checks credential validity across all facilities:
                                 Kerberos ticket expiry (lxplus), sshproxy
                                 certificate validity (NERSC), SSH certificate
                                 validity (LRC), and key presence (S3DF).
```

### Prerequisites

| Facility | Requirement |
|----------|-------------|
| lxplus   | Kerberos client (`kinit`, `klist`) — pre-installed on macOS; `krb5-user` on Debian/Ubuntu; [MIT Kerberos for Windows](https://web.mit.edu/kerberos/dist/) on Windows |
| NERSC    | `curl` — `sshproxy` binary is auto-downloaded on first run |
| LRC      | `git` — `lrc-scripts` repo is auto-cloned on first run |
| S3DF     | `ssh-keygen` — standard, pre-installed everywhere |

#### Windows

The scripts are bash and run on Windows under **Git Bash** (or
MSYS2/Cygwin) and **WSL**. WSL behaves exactly like Linux and needs
nothing special. Under Git Bash:

- **lxplus** — install MIT Kerberos for Windows first so `kinit` is on
  PATH. The generated config at `~/.config/krb5.conf` is passed to
  `kinit` via `KRB5_CONFIG` in Windows path form automatically.
- **NERSC** — the `windows-universal` MSIX package is downloaded from
  the NERSC portal and installed per-user via `Add-AppxPackage` (no
  admin rights needed). The `sshproxy` command then resolves from
  `%LOCALAPPDATA%\Microsoft\WindowsApps`.
- **LRC / S3DF** — work as-is; `git` and `ssh-keygen` ship with Git Bash.

### Installation

#### 1. Source setup.sh

```bash
source setup.sh
```

This makes all scripts executable and defines the aliases below.
Re-run this in any new terminal session, or add
`source /absolute/path/to/dotfiles/setup.sh` to your own
`.zshrc`/`.bashrc` to make it permanent.

| Alias | Description |
|-------|-------------|
| `ssh-remote-config` | Set up SSH host configs |
| `ssh-remote-auth`   | Refresh SSH credentials for a host |
| `ssh-remote-status` | Check current credential status |

#### 2. Install SSH host configs

```bash
ssh-remote-config --lxplus <cern-username> --nersc <nersc-username> --lrc <lrc-username> --s3df <s3df-username>

# Or the same username for all hosts
ssh-remote-config --all <username>
```

Re-running is safe — conf files are overwritten but `Include` lines
are never duplicated.

#### 3. Set up credentials

```bash
ssh-remote-auth --host lxplus   # ~25h Kerberos ticket
ssh-remote-auth --host nersc    # ~24h sshproxy certificate
ssh-remote-auth --host lrc      # ~12h SSH certificate
ssh-remote-auth --host s3df     # ed25519 key pair
```

Usernames are auto-resolved from the SSH config installed in step 2.
Pass `-u <username>` to override (e.g. for a secondary account at the
same facility — see [Username auto-resolution](#username-auto-resolution)).

> **S3DF note:** after running, upload the printed public key at
> <https://s3df-sshkeys.slac.stanford.edu> to activate it.

### Daily Use

```bash
# Check what's still valid
ssh-remote-status

# Refresh as needed
ssh-remote-auth --host lxplus
ssh-remote-auth --host nersc
ssh-remote-auth --host lrc

# Connect
ssh lxplus
ssh nersc        # alias for perlmutter
ssh perlmutter
ssh lrc
ssh s3df
```

### Username auto-resolution

`ssh-remote-auth` does not require `-u` for hosts you've installed
via `ssh-remote-config`. The dispatcher resolves the username with
`ssh -G <host>`, which reads `~/.ssh/config` and any included
drop-ins.

```bash
$ ssh-remote-auth --host lxplus
==> Using username 'alice' (from SSH config)
...
```

Pass `-u` to override for a one-off (a secondary account, a colleague's
account on a shared workstation, etc.):

```bash
ssh-remote-auth --host lxplus -u bob
```

If no host-specific `User` is set in your SSH config and `-u` is
omitted, the dispatcher errors out and points you at the right
fix rather than silently trying `kinit $USER@CERN.CH`.

For **lrc** specifically: the resolved username is also pre-filled
into the upstream `request_cert.sh` interactive prompt, so only PIN
and OTP need to be typed.

### Adding a New Host

**1. Register in `ssh/keys/setup_ssh_key.sh`:**

```bash
SUPPORTED_HOSTS="lxplus nersc s3df lrc <newhost>"
NEEDS_USER_<newhost>=true   # or false if credentials are handled internally
```

**2. Add a config template in `ssh/config/setup_ssh_configs.sh`:**

```bash
conf_<newhost>() {
    local USER="$1"
    cat << CONF
Host <newhost>
    HostName <newhost>.example.com
    User $USER
    ServerAliveInterval 60
    ServerAliveCountMax 3
CONF
}
```

And add `<newhost>` to `SUPPORTED_HOSTS` at the top of that script.

**3. Add `ssh/keys/setup_<newhost>_key.sh`** and make it executable.

### Credential Locations

Credentials are stored outside the repo and are never committed.

| Facility | Credential path |
|----------|----------------|
| lxplus   | Kerberos ticket cache (in memory) |
| NERSC    | `~/.ssh/nersc`, `~/.ssh/nersc-cert.pub` |
| LRC      | `~/.ssh/ssh_certs/lrc_cert` |
| S3DF     | `~/.ssh/s3df/key`, `~/.ssh/s3df/key.pub` |
