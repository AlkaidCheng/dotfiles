#!/usr/bin/env bash
# setup-labels.sh — apply a standard label set to one or more GitHub repos.
#
# Behavior per repo:
#   1. Creates or updates labels in the managed set below.
#   2. Deletes GitHub's default labels that aren't in the managed set
#      (e.g. "question", "documentation").
#   3. Leaves all other labels alone — anything custom is preserved.
#
# Usage:
#   setup-labels.sh                          # current directory
#   setup-labels.sh path/to/repo             # one repo
#   setup-labels.sh repo1 repo2 ../repo3     # several

set -euo pipefail

# name|color|description  (color = 6-char hex, no '#')
labels=(
  # Type — unprefixed: these are the most common labels and matching
  # the unprefixed convention (incl. GitHub's own defaults) reads better.
  "bug|d73a4a|Something isn't working"
  "feature|a2eeef|New feature or request"
  "enhancement|84b6eb|Improvement to existing functionality"
  "perf|5319e7|Performance improvement or optimization"
  "refactor|fbca04|Code change that neither fixes a bug nor adds a feature"
  "docs|0075ca|Documentation only"
  "design|8a63d2|Design documents, proposals, architecture"
  "test|bfd4f2|Adding or updating tests"
  "benchmark|1d76db|Adding or updating benchmarks or measurement harnesses"
  "ci|c5def5|Continuous integration and workflows"
  "deps|f9d0c4|Dependency updates"
  "release|2ea44f|Release engineering: versioning, changelog, packaging"
  "chore|cfd3d7|Maintenance and tooling"

  # Modifiers — stack on a type label rather than replacing it
  "breaking|e11d21|Breaking change to a public API or stable format"

  # Priority
  "priority: critical|b60205|Drop everything"
  "priority: high|d93f0b|Should be done soon"
  "priority: medium|fbca04|Normal queue"
  "priority: low|0e8a16|Nice to have"

  # Status
  "status: blocked|b60205|Cannot proceed"
  "status: in progress|fbca04|Actively being worked on"
  "status: needs review|0075ca|Waiting on review"
  "status: needs info|d876e3|Awaiting more information"

  # Resolution
  "wontfix|ffffff|This will not be worked on"
  "duplicate|cfd3d7|Already exists"
  "invalid|e4e669|Not actionable as filed"

  # Community
  "good first issue|7057ff|Good for newcomers"
  "help wanted|008672|Extra attention is welcome"
)

# GitHub's default labels on every new repo. Any of these NOT in the
# managed set above will be deleted, so the final label list matches
# the managed set plus whatever was custom-created.
github_defaults=(
  "bug"
  "documentation"
  "duplicate"
  "enhancement"
  "good first issue"
  "help wanted"
  "invalid"
  "question"
  "wontfix"
)

apply_labels() {
  local repo_path="$1"

  if [[ ! -d "$repo_path" ]]; then
    echo "  skip: '$repo_path' is not a directory" >&2
    return 1
  fi
  if ! git -C "$repo_path" rev-parse --git-dir >/dev/null 2>&1; then
    echo "  skip: '$repo_path' is not a git repository" >&2
    return 1
  fi

  echo "==> $repo_path"
  pushd "$repo_path" >/dev/null

  # One snapshot of existing labels per repo
  local existing
  existing=$(gh label list --limit 200 --json name --jq '.[].name')

  # Collect managed names for the default-pruning check below
  local managed_names=() entry name color desc
  for entry in "${labels[@]}"; do
    IFS='|' read -r name _ _ <<< "$entry"
    managed_names+=("$name")
  done

  # Create or update managed labels
  for entry in "${labels[@]}"; do
    IFS='|' read -r name color desc <<< "$entry"
    if grep -Fxq "$name" <<< "$existing"; then
      gh label edit "$name" --color "$color" --description "$desc" >/dev/null
      echo "  updated: $name"
    else
      gh label create "$name" --color "$color" --description "$desc" >/dev/null
      echo "  created: $name"
    fi
  done

  # Delete GitHub defaults that aren't part of the managed set
  local default
  for default in "${github_defaults[@]}"; do
    if printf '%s\n' "${managed_names[@]}" | grep -Fxq "$default"; then
      continue   # managed (already updated above)
    fi
    if grep -Fxq "$default" <<< "$existing"; then
      gh label delete "$default" --yes >/dev/null
      echo "  deleted: $default (github default, not in managed set)"
    fi
  done

  popd >/dev/null
}

if [[ $# -eq 0 ]]; then
  set -- "."
fi

status=0
for repo in "$@"; do
  apply_labels "$repo" || status=1
done

exit "$status"
