# dotfiles

Personal dotfiles and environment setup scripts.

## Contents

| Path | Description |
|------|-------------|
| `ssh/` | SSH config and credential setup scripts for HPC facilities |

---

## ssh/

Scripts for managing SSH configs and credentials across HPC facilities.

### Directory Layout

```
ssh/
├── config/
│   └── setup_ssh_configs.sh   # Generate and install per-host SSH configs
└── keys/
    ├── setup_ssh_key.sh        # Master dispatcher (start here)
    ├── setup_lxplus_key.sh     # CERN lxplus  — Kerberos via kinit
    ├── setup_nersc_key.sh      # NERSC         — sshproxy certificate
    ├── setup_lrc_key.sh        # LRC           — request_cert.sh
    ├── setup_s3df_key.sh       # SLAC S3DF     — ed25519 key generation
    └── status_ssh_keys.sh      # Check credential status across all hosts
```

### Prerequisites

| Facility | Requirement |
|----------|-------------|
| lxplus   | Kerberos client (`kinit`, `klist`) — pre-installed on macOS; `krb5-user` on Debian/Ubuntu |
| NERSC    | `curl` — `sshproxy` binary is auto-downloaded on first run |
| LRC      | `git` — `lrc-scripts` repo is auto-cloned on first run |
| S3DF     | `ssh-keygen` — standard, pre-installed everywhere |

### Installation

#### 1. Make scripts executable

After cloning, restore executable permissions:

```bash
chmod +x ssh/config/*.sh ssh/keys/*.sh
```

Or track permissions permanently in git:

```bash
git update-index --chmod=+x ssh/config/*.sh ssh/keys/*.sh
```

#### 2. Install SSH host configs

Generates drop-in config files under `~/.ssh/configs/` and registers
them in `~/.ssh/config` via `Include` directives. Re-running is safe —
it overwrites the conf files but never duplicates `Include` lines.

```bash
# Set up individual hosts with different usernames
./ssh/config/setup_ssh_configs.sh --lxplus <cern-username> --nersc <nersc-username> --lrc <lrc-username> --s3df <s3df-username>

# Or set up all hosts with the same username
./ssh/config/setup_ssh_configs.sh --all <username>
```

#### 3. Set up credentials

Credentials are time-limited and need to be refreshed regularly. Use the
master dispatcher:

```bash
./ssh/keys/setup_ssh_key.sh --host lxplus -u <cern-username>   # ~25h Kerberos ticket
./ssh/keys/setup_ssh_key.sh --host nersc  -u <nersc-username>  # ~24h sshproxy certificate
./ssh/keys/setup_ssh_key.sh --host lrc                         # ~12h SSH certificate (prompts for credentials)
./ssh/keys/setup_ssh_key.sh --host s3df  -u <s3df-username>    # generates a new ed25519 key pair
```

> **S3DF note:** after running the S3DF script, upload the printed public
> key at <https://s3df-sshkeys.slac.stanford.edu> to activate it.

### Daily Use

```bash
# Check which credentials are still valid
./ssh/keys/status_ssh_keys.sh

# Refresh as needed
./ssh/keys/setup_ssh_key.sh --host lxplus -u <cern-username>
./ssh/keys/setup_ssh_key.sh --host nersc  -u <nersc-username>
./ssh/keys/setup_ssh_key.sh --host lrc

# Connect
ssh lxplus
ssh nersc        # alias for perlmutter
ssh perlmutter
ssh lrc
ssh s3df
```

### Adding a New Host

**1. Register the host in `ssh/keys/setup_ssh_key.sh`:**

```bash
SUPPORTED_HOSTS="lxplus nersc s3df lrc <newhost>"
NEEDS_USER_<newhost>=true   # or false if the script handles credentials internally
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

**3. Add a `ssh/keys/setup_<newhost>_key.sh` script** and make it executable.

### Credential Locations

Credentials are stored outside the repo and are never committed.

| Facility | Credential path |
|----------|----------------|
| lxplus   | Kerberos ticket cache (in memory) |
| NERSC    | `~/.ssh/nersc`, `~/.ssh/nersc-cert.pub` |
| LRC      | `~/.ssh/ssh_certs/lrc_cert` |
| S3DF     | `~/.ssh/s3df/key`, `~/.ssh/s3df/key.pub` |
