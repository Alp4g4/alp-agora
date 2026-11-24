#!/bin/bash
# validate-issue.sh - validate a GitHub issue as a technical specification.
#
# Pure function: never calls gh or the network itself. The caller fetches the
# issue and pipes the JSON in, which keeps this script testable with fixtures.
set -eo pipefail

usage() {
  cat <<'EOF'
validate-issue.sh - validate a GitHub issue as a technical specification

USAGE
  gh issue view <issue URL> --json number,title,body,state,url,labels | validate-issue.sh
  validate-issue.sh < issue.json
  validate-issue.sh issue.json

Reads the JSON produced by `gh issue view --json number,title,body,state,url,labels`
(on stdin, or from a file given as the first argument) and checks that the issue is
usable as a technical specification.

CHECKS
  - required fields are present: number, title, body, state, url, labels
  - state is OPEN
  - body has a "## Context" section
  - body has a "## Acceptance criteria" section with at least one checklist item
  - body has a "## Out of scope" section
  - at least one label maps to a known skill (see LABEL -> SKILL below)

  Headings must match exactly, including case: "## Context", not "## context"
  or "### Context".

LABEL -> SKILL
  go            go:go-clean-architecture
  go-sql        go:go-sql
  go-ssr        go:go-ssr
  ui-ux-design  web-design:ui-ux-design

OUTPUT
  A single JSON object on stdout. Exit code is 0 when valid, 1 otherwise.

  On success:
    {"valid":true,"number":3,"title":"...","url":"...","state":"OPEN",
     "skills":["web-design:ui-ux-design"],"acceptance_criteria":6}

  On failure:
    {"valid":false,"errors":["issue state is CLOSED, it must be OPEN"]}

EXAMPLE
  gh issue view https://github.com/Alp4g4/alp-drive/issues/3 \
    --json number,title,body,state,url,labels | validate-issue.sh
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

fail() {
  jq -n --argjson errs "$1" '{valid:false, errors:$errs}'
  exit 1
}

errors_to_json() {
  jq -R . | jq -s .
}

if ! command -v jq >/dev/null 2>&1; then
  fail "$(printf '%s\n' "jq is required" | errors_to_json)"
fi

if [[ -n "${1:-}" ]]; then
  input=$(cat "$1")
else
  input=$(cat)
fi

if ! input_ok=$(echo "$input" | jq -e . 2>/dev/null); then
  fail "$(printf '%s\n' "input is not valid JSON" | errors_to_json)"
fi

errors=()

for field in number title body state url labels; do
  if ! echo "$input" | jq -e "has(\"$field\") and .$field != null" >/dev/null 2>&1; then
    errors+=("missing required field: $field")
  fi
done

if [[ ${#errors[@]} -gt 0 ]]; then
  fail "$(printf '%s\n' "${errors[@]}" | errors_to_json)"
fi

number=$(echo "$input" | jq -r '.number')
title=$(echo "$input" | jq -r '.title')
url=$(echo "$input" | jq -r '.url')
state=$(echo "$input" | jq -r '.state')
body=$(echo "$input" | jq -r '.body')

if [[ "$state" != "OPEN" ]]; then
  errors+=("issue state is $state, it must be OPEN")
fi

# prints the body between an exact "## $1" heading and the next "## " heading
section() {
  awk -v heading="## $1" '
    $0 == heading { found=1; next }
    found && /^##[[:space:]]/ { exit }
    found { print }
  ' <<<"$body"
}

for required in "Context" "Acceptance criteria" "Out of scope"; do
  if [[ -z "$(section "$required")" ]]; then
    errors+=("missing required section: ## $required")
  fi
done

ac_count=$(section "Acceptance criteria" | grep -cE '^[[:space:]]*-[[:space:]]*\[[ xX]\]' || true)
if [[ "$ac_count" -eq 0 ]]; then
  errors+=("## Acceptance criteria has no checklist items")
fi

skill_for_label() {
  case "$1" in
    go) echo "go:go-clean-architecture" ;;
    go-sql) echo "go:go-sql" ;;
    go-ssr) echo "go:go-ssr" ;;
    ui-ux-design) echo "web-design:ui-ux-design" ;;
    *) echo "" ;;
  esac
}

labels=()
while IFS= read -r label; do
  [[ -n "$label" ]] && labels+=("$label")
done < <(echo "$input" | jq -r '.labels[].name')

skills=()
for l in "${labels[@]}"; do
  s=$(skill_for_label "$l")
  [[ -n "$s" ]] && skills+=("$s")
done

if [[ ${#skills[@]} -eq 0 ]]; then
  if [[ ${#labels[@]} -eq 0 ]]; then
    errors+=("no label maps to a known skill (issue has no labels)")
  else
    errors+=("no label maps to a known skill (labels: ${labels[*]})")
  fi
fi

if [[ ${#errors[@]} -gt 0 ]]; then
  fail "$(printf '%s\n' "${errors[@]}" | errors_to_json)"
fi

skills_json=$(printf '%s\n' "${skills[@]}" | jq -R . | jq -s 'unique')

jq -n \
  --argjson number "$number" \
  --arg title "$title" \
  --arg url "$url" \
  --arg state "$state" \
  --argjson skills "$skills_json" \
  --argjson ac "$ac_count" \
  '{valid:true, number:$number, title:$title, url:$url, state:$state, skills:$skills, acceptance_criteria:$ac}'
