#!/usr/bin/env bash
# setup_gh_repo.sh — give one or more GitHub repos the standard settings.
#
# Behavior per repo:
#   1. Applies the standard labels with setup_gh_labels.sh.
#   2. Turns on "Automatically delete head branches".
#   3. Creates or updates the default branch's ruleset: no deletion, no force
#      push, changes only through pull requests, and, when there are any to
#      require, passing status checks on an up-to-date branch.
#
# Re-running is safe: the ruleset is found by name and updated in place, and it
# keeps its required checks unless new ones are given. The ruleset stops direct
# pushes to the default branch for everyone, a scheduled job that commits there
# included. GitHub offers rulesets on private repos only on paid plans; a refusal
# is reported and the script moves on to the next repo.
#
# Usage:
#   setup_gh_repo.sh                                # current directory
#   setup_gh_repo.sh path/to/repo1 path/to/repo2    # several
#   setup_gh_repo.sh --checks-from BRANCH repo      # require the Actions jobs that ran on a ref
#   setup_gh_repo.sh --check "Lint" --check "Test"  # require these checks
#   setup_gh_repo.sh --dry-run repo                 # print the ruleset, change nothing

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

ruleset_name="main: changes only through pull requests"

# Required checks must come from GitHub Actions, from `gh api /apps/github-actions`.
actions_app_slug="github-actions"
actions_app_id=15368

check_names=()
checks_from=""
dry_run=false
repos=()

print_usage() {
  sed -n '2,/^$/s/^# \{0,1\}//p' "${BASH_SOURCE[0]}"
}

# Print `$1` as a JSON string. Check names hold no control characters.
json_string() {
  local text=${1//\\/\\\\}
  printf '"%s"' "${text//\"/\\\"}"
}

# Print the names of the Actions jobs that ran on a ref, one per line.
action_job_names() {
  local slug="$1" ref="$2" sha
  sha=$(git rev-parse --verify --quiet "$ref^{commit}") || return 1
  gh api "repos/$slug/commits/$sha/check-runs?per_page=100" \
    --jq ".check_runs[] | select(.app.slug == \"$actions_app_slug\") | .name" |
    sort -u
}

# Print a JSON array of required checks from names read on standard input.
checks_json() {
  local name separator="" json="["
  while IFS= read -r name; do
    json+="$separator{\"context\": $(json_string "$name"), \"integration_id\": $actions_app_id}"
    separator=", "
  done
  printf '%s]' "$json"
}

# Print the ruleset's required checks: those asked for, else those it already has.
required_checks_json() {
  local slug="$1" ruleset_id="$2" names
  if [[ -n "$checks_from" ]]; then
    names=$(action_job_names "$slug" "$checks_from") || names=""
    if [[ -z "$names" ]]; then
      echo "  no Actions jobs found on '$checks_from'" >&2
      return 1
    fi
    checks_json <<< "$names"
  elif ((${#check_names[@]})); then
    printf '%s\n' "${check_names[@]}" | checks_json
  elif [[ -n "$ruleset_id" ]]; then
    gh api "repos/$slug/rulesets/$ruleset_id" --jq \
      '[.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks[]]'
  else
    printf '[]'
  fi
}

# Print the ruleset for `$1`, a JSON array of required checks.
ruleset_json() {
  local checks="$1" status_rule=""
  if [[ "$checks" != "[]" ]]; then
    status_rule=",
    {
      \"type\": \"required_status_checks\",
      \"parameters\": {
        \"do_not_enforce_on_create\": false,
        \"strict_required_status_checks_policy\": true,
        \"required_status_checks\": $checks
      }
    }"
  fi
  cat <<EOF
{
  "name": $(json_string "$ruleset_name"),
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [],
  "conditions": {"ref_name": {"include": ["~DEFAULT_BRANCH"], "exclude": []}},
  "rules": [
    {"type": "deletion"},
    {"type": "non_fast_forward"},
    {
      "type": "pull_request",
      "parameters": {
        "allowed_merge_methods": ["merge", "squash", "rebase"],
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_approving_review_count": 0,
        "required_review_thread_resolution": false
      }
    }$status_rule
  ]
}
EOF
}

apply_ruleset() {
  local slug="$1" ruleset_id checks ruleset
  ruleset_id=$(gh api "repos/$slug/rulesets?per_page=100" --jq \
    ".[] | select(.name == $(json_string "$ruleset_name")) | .id") || return 1
  checks=$(required_checks_json "$slug" "$ruleset_id") || return 1
  ruleset=$(ruleset_json "$checks")

  if [[ "$dry_run" == true ]]; then
    echo "  would write this ruleset:"
    printf '%s\n' "$ruleset"
  elif [[ -n "$ruleset_id" ]]; then
    gh api -X PUT "repos/$slug/rulesets/$ruleset_id" --input - <<< "$ruleset" >/dev/null || return 1
    echo "  ruleset: updated"
  else
    gh api -X POST "repos/$slug/rulesets" --input - <<< "$ruleset" >/dev/null || return 1
    echo "  ruleset: created"
  fi
}

# A subshell, so that changing directory ends with the repo.
apply_settings() (
  local repo_path="$1" slug

  if [[ ! -d "$repo_path" ]]; then
    echo "  skip: '$repo_path' is not a directory" >&2
    return 1
  fi
  if ! git -C "$repo_path" rev-parse --git-dir >/dev/null 2>&1; then
    echo "  skip: '$repo_path' is not a git repository" >&2
    return 1
  fi

  echo "==> $repo_path"
  cd "$repo_path"
  if ! slug=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null); then
    echo "  skip: '$repo_path' has no GitHub repository" >&2
    return 1
  fi

  if [[ "$dry_run" == true ]]; then
    echo "  would apply labels and turn on head branch deletion for $slug"
  else
    bash "$script_dir/setup_gh_labels.sh" . >/dev/null || return 1
    echo "  labels: applied"
    gh api -X PATCH "repos/$slug" -F delete_branch_on_merge=true >/dev/null || return 1
    echo "  head branch deletion: on"
  fi
  apply_ruleset "$slug"
)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)
      check_names+=("${2:?--check needs a name}")
      shift 2
      ;;
    --checks-from)
      checks_from="${2:?--checks-from needs a ref}"
      shift 2
      ;;
    --dry-run)
      dry_run=true
      shift
      ;;
    -h | --help)
      print_usage
      exit 0
      ;;
    -*)
      echo "unknown option: $1" >&2
      exit 2
      ;;
    *)
      repos+=("$1")
      shift
      ;;
  esac
done

if ((${#repos[@]} == 0)); then
  repos=(".")
fi

status=0
for repo in "${repos[@]}"; do
  apply_settings "$repo" || status=1
done

exit "$status"
