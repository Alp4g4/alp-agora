#!/bin/bash
# validate-tech-spec.sh: checks that a tech spec file follows the format below.
#
# Usage:   validate-tech-spec.sh <tech-specs/PROJ-142.md>
#          validate-tech-spec.sh --help
# Success: exit 0, prints the metadata as key=value lines (id, url, base, stack, type, story, depends_on, acceptance_criteria).
# Failure: exit 1, prints every error at once on stderr.
#
# ── Tech spec format ─────────────────────────────────────────────────────────────
# One markdown file per tech spec, named <id>.md, in the tech-specs/ folder of the project.
#
#   ---
#   id: PROJ-142              # required. Uppercase key + number, must equal the file name.
#                             #   → the branch name must contain it (proj-142, feat/PROJ-142-…),
#                             #     commit prefix, PR title.
#   project_name: my-api
#   url: https://github.com/org/my-api   # required. URL of the remote git repository
#                             #   (https://…, git@host:owner/name.git or ssh://…).
#                             #   → the agent only works in a clone whose "origin" is this repository.
#   base: main                # optional, default main.
#                             #   → branch to start from and target of the PR.
#   stack: go, go-sql         # required. A comma-separated list of components:
#                             #     go      Go clean architecture (always, for a Go project)
#                             #     go-sql  the tech spec touches the schema, a migration or a query
#                             #     go-ssr  the tech spec touches a server-rendered page
#                             #   go-sql and go-ssr come with go.
#                             #   → which skills and checks the agent uses (never guessed).
#   type: bug                 # required. feature | bug | refactor | chore
#                             #   → how the agent tests:
#                             #     feature  each acceptance criterion gets a test (or a manual check in the PR)
#                             #     bug      first a failing test that reproduces the bug, then the fix
#                             #     refactor no behaviour change, existing tests pass unmodified
#                             #     chore    no new tests required, all checks must pass
#   story: PROD-12            # optional. The product spec (story) this tech spec comes from.
#   depends_on: PROJ-141      # optional. Comma-separated ids of tech specs to deliver first.
#   ---
#
#   ## Context                # required, not empty. Why the work exists.
#   The /healthz endpoint returns 500 when the DB is down; the load balancer
#   then kills healthy pods.
#
#   ## Acceptance criteria    # required, at least one "- [ ]" item. The definition of done.
#   - [ ] GET /healthz returns 200 {"status":"ok"} even when the DB is unreachable
#   - [ ] Covered by a unit test on the HTTP handler
#
#   ## Technical notes        # optional. Constraints, files to touch, things to avoid.
#   No new dependencies.
#
#   ## Out of scope           # optional, recommended. What the agent must NOT do.
#   Readiness checks on the database.
#
# ──────────────────────────────────────────────────────────────────────────────

set -u

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  sed -n '2,/^# ──────────────────────────────────────────────────────────────────────────────$/p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
fi

file="${1:-}"
[ -z "$file" ] && { echo "usage: $0 <tech-spec.md>" >&2; exit 2; }
[ -f "$file" ] || { echo "tech spec not found: $file" >&2; exit 1; }

errors=()
err() { errors+=("$1"); }

# --- Front matter -----------------------------------------------------------
[ "$(head -n1 "$file")" = "---" ] || { echo "front matter missing: the file must start with a '---' line" >&2; exit 1; }
fm=$(awk 'NR==1{next} /^---[[:space:]]*$/{exit} {print}' "$file")
body=$(awk 'f>=2{print} /^---[[:space:]]*$/{f++}' "$file")

id=""; url=""; base=""; stack=""; type=""; story=""; depends_on=""
while IFS= read -r line; do
  line="${line%%#*}"                                   # strip comments
  line="$(echo "$line" | sed -E 's/[[:space:]]+$//')"
  [ -z "$line" ] && continue
  key="$(echo "$line" | sed -E 's/^([A-Za-z_]+):.*/\1/')"
  val="$(echo "$line" | sed -E 's/^[A-Za-z_]+:[[:space:]]*//')"
  case "$key" in
    id) id="$val" ;; url) url="$val" ;; base) base="$val" ;;
    stack) stack="$val" ;; type) type="$val" ;;
    story) story="$val" ;; depends_on) depends_on="$val" ;;
    *) err "unknown field '$key' (allowed: id, url, base, stack, type, story, depends_on)" ;;
  esac
done <<< "$fm"

# id
if [ -z "$id" ]; then err "id: required"
elif ! echo "$id" | grep -Eq '^[A-Z][A-Z0-9]*-[0-9]+$'; then err "id: '$id' must look like PROJ-142"
elif [ "$(basename "$file" .md)" != "$id" ]; then err "id: '$id' does not match the file name '$(basename "$file")'"
fi

# stack: a comma-separated list of components, printed back as "go,go-sql"
components=()
if [ -z "$stack" ]; then
  err "stack: required, a list of components (go, go-sql, go-ssr)"
else
  IFS=',' read -ra parts <<< "$stack"
  for c in "${parts[@]}"; do
    c="$(echo "$c" | tr -d '[:space:]')"
    case "$c" in
      go|go-sql|go-ssr)
        case " ${components[*]:-} " in
          *" $c "*) err "stack: '$c' is listed twice" ;;
          *) components+=("$c") ;;
        esac ;;
      "") err "stack: '$stack' has an empty component" ;;
      *)  err "stack: '$c' is unknown (go, go-sql, go-ssr)" ;;
    esac
  done
  case " ${components[*]:-} " in
    *" go-sql "* | *" go-ssr "*)
      case " ${components[*]} " in *" go "*) ;; *) err "stack: go-sql and go-ssr come with go (stack: go, ${components[*]// /, })" ;; esac ;;
  esac
  stack="$(IFS=','; echo "${components[*]:-}")"
fi

# type
case "$type" in
  feature|bug|refactor|chore) ;;
  "") err "type: required (feature | bug | refactor | chore)" ;;
  *)  err "type: '$type' is unknown (feature | bug | refactor | chore)" ;;
esac

# depends_on (optional): comma-separated ids, never itself
if [ -n "$depends_on" ]; then
  deps=()
  IFS=',' read -ra parts <<< "$depends_on"
  for d in "${parts[@]}"; do
    d="$(echo "$d" | tr -d '[:space:]')"
    if ! echo "$d" | grep -Eq '^[A-Z][A-Z0-9]*-[0-9]+$'; then err "depends_on: '$d' must look like PROJ-141"
    elif [ "$d" = "$id" ]; then err "depends_on: a tech spec cannot depend on itself"
    else deps+=("$d"); fi
  done
  depends_on="$(IFS=','; echo "${deps[*]:-}")"
fi

# base (optional, default main)
[ -z "$base" ] && base="main"

# url: URL of the remote repository (the match with the local clone is checked by the senior-dev agent)
if [ -z "$url" ]; then err "url: required (URL of the remote repository, e.g. https://github.com/org/my-api)"
elif ! echo "$url" | grep -Eq '^(https://[^/[:space:]]+/[^/[:space:]]+/[^/[:space:]]+/?|git@[^:[:space:]]+:[^/[:space:]]+/[^/[:space:]]+|ssh://([^@/]+@)?[^/[:space:]]+/[^/[:space:]]+/[^/[:space:]]+)$'; then
  err "url: '$url' is not a repository URL (https://host/owner/name, git@host:owner/name.git or ssh://…)"
fi

# --- Body sections ------------------------------------------------------------
section() { # prints the content of a "## <name>" section (case-insensitive)
  echo "$body" | awk -v name="$1" '
    tolower($0) ~ "^## +" tolower(name) "[[:space:]]*$" {on=1; next}
    /^## / {on=0}
    on {print}'
}

ctx="$(section "Context" | grep -Ev '^[[:space:]]*$')"
[ -z "$ctx" ] && err "## Context: required and must not be empty"

ac="$(section "Acceptance criteria")"
ac_count=$(echo "$ac" | grep -Ec '^[[:space:]]*- \[[ xX]\] +[^[:space:]]')
[ "$ac_count" -eq 0 ] && err "## Acceptance criteria: required, with at least one '- [ ] ...' item"

# leftovers from the template
grep -q 'Concrete, testable statement' "$file" && err "body: still contains template placeholder text"

# --- Result -------------------------------------------------------------------
if [ ${#errors[@]} -gt 0 ]; then
  echo "Tech spec $file is invalid:" >&2
  for e in "${errors[@]}"; do echo "  - $e" >&2; done
  exit 1
fi

printf 'id=%s\url=%s\nbase=%s\nstack=%s\ntype=%s\nstory=%s\ndepends_on=%s\nacceptance_criteria=%s\n' \
  "$id" "$url" "$base" "$stack" "$type" "$story" "$depends_on" "$ac_count"
