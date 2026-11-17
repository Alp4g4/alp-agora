#!/bin/bash
# setup-repo.sh: prepares an isolated git worktree for a ticket, up to date with its base branch.
#
# Usage:   setup-repo.sh <repo-url> <base> <branch>
#            repo-url the ticket's repo (from validate-ticket.sh): the "origin" remote of the clone
#                     you are running in must point to it (https and ssh forms are equivalent)
#            base     the ticket's base branch (e.g. main)
#            branch   <id lowercase>-<short-description>, e.g. proj-142-healthz-endpoint
# Success: exit 0, prints key=value lines:
#            worktree=<path>   folder where ALL the work happens
#            branch=<name>
#            base_ref=<ref>    what the branch was created from (origin/<base>)
#            status=created|reused
#            behind=<n>        commits the branch is behind base_ref (only when reused)
# Failure: exit 1 with the reason on stderr.
#
# Worktrees live in <repo>/.worktrees/<branch>. The script adds ".worktrees/" and "PLAN.md"
# to the repo's local exclude file (.git/info/exclude): they are never committed, and nothing
# in your tracked .gitignore changes.
set -euo pipefail

die() { echo "setup-repo: $*" >&2; exit 1; }

[ $# -eq 3 ] || { sed -n '4,8p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
repo="$1"; base="$2"; branch="$3"

# --- Right repository? --------------------------------------------------------
# normalize a git URL to host/owner/name: https://github.com/Org/Api.git, git@github.com:org/api,
# ssh://git@github.com/org/api.git → github.com/org/api
normalize() {
  echo "$1" | tr 'A-Z' 'a-z' | sed -E \
    -e 's#^[a-z+]+://##' -e 's#^[^@/]+@##' -e 's#^([^/:]+):#\1/#' -e 's#/+$##' -e 's#\.git$##'
}
here="$(git rev-parse --show-toplevel 2>/dev/null)" || die "you are not inside a git repository ($(pwd))"
origin="$(git remote get-url origin 2>/dev/null)" || die "this clone has no 'origin' remote"
[ "$(normalize "$origin")" = "$(normalize "$repo")" ] || \
  die "wrong repository: this clone's origin is $origin, the ticket is for $repo"
# work from the main checkout, even if called from inside a worktree
root="$(cd "$(git rev-parse --git-common-dir)/.." && pwd -P)"
cd "$root"

# --- Branch name ---------------------------------------------------------------
echo "$branch" | grep -Eq '^[a-z][a-z0-9]*-[0-9]+(-[a-z0-9]+)+$' || \
  die "branch '$branch' must look like proj-142-short-description (lowercase id, then words separated by -)"

# --- Fetch -----------------------------------------------------------------------
git fetch --quiet origin || die "git fetch origin failed"
git rev-parse --verify --quiet "origin/$base" >/dev/null || die "base branch '$base' not found on origin"
base_ref="origin/$base"

# --- Local excludes (shared by all worktrees) --------------------------------------
exclude="$(git rev-parse --git-common-dir)/info/exclude"
mkdir -p "$(dirname "$exclude")"; touch "$exclude"
for pattern in ".worktrees/" "PLAN.md"; do
  grep -qxF "$pattern" "$exclude" || echo "$pattern" >> "$exclude"
done

# --- Worktree ----------------------------------------------------------------------
path="$root/.worktrees/$branch"
existing="$(git worktree list --porcelain | awk -v b="refs/heads/$branch" '
  /^worktree /{wt=substr($0,10)} $0=="branch " b {print wt}')"

if [ -n "$existing" ]; then
  path="$existing"; status="reused"            # keep the work already done, never reset it
elif git rev-parse --verify --quiet "refs/heads/$branch" >/dev/null; then
  git worktree add --quiet "$path" "$branch" || die "could not create worktree for existing branch $branch"
  status="reused"
elif git rev-parse --verify --quiet "refs/remotes/origin/$branch" >/dev/null; then
  git worktree add --quiet --track -b "$branch" "$path" "origin/$branch" || die "could not create worktree from origin/$branch"
  status="reused"
else
  git worktree add --quiet --no-track -b "$branch" "$path" "$base_ref" || die "could not create worktree $path"
  status="created"
fi

echo "worktree=$path"
echo "branch=$branch"
echo "base_ref=$base_ref"
echo "status=$status"
[ "$status" = "reused" ] && echo "behind=$(git rev-list --count "$branch..$base_ref")"
exit 0
