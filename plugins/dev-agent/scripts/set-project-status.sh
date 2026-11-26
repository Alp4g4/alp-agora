#!/bin/bash
# set-project-status.sh - move a GitHub issue's Project (v2) Status field.
set -eo pipefail

usage() {
  cat <<'EOF'
set-project-status.sh - move a GitHub issue's Project (v2) Status field

USAGE
  set-project-status.sh [--project <project title>] [--dry-run] <issue URL> <status name>

Looks up the project item for the given issue, finds the "Status" field's
option matching <status name> (exact match, case-sensitive), and sets it.

If the issue is on more than one project, pass --project "<title>" to pick
one; otherwise the script lists the projects it found and exits 1.

--dry-run performs every lookup but skips the mutation, printing what it
would have done. Use it to test the script without changing real data.

REQUIRES
  gh authenticated with the "project" scope:
    gh auth refresh -s project,read:project

OUTPUT
  A single JSON object on stdout. Exit code is 0 on success, 1 otherwise.

  {"ok":true,"project":"Roadmap","status":"In progress"}
  {"ok":false,"error":"issue is on 2 projects: Roadmap, Backlog. Pass --project."}

EXAMPLE
  set-project-status.sh https://github.com/Alp4g4/alp-drive/issues/3 "In progress"
EOF
}

dry_run=false
project_filter=""
args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --dry-run) dry_run=true; shift ;;
    --project) project_filter="$2"; shift 2 ;;
    *) args+=("$1"); shift ;;
  esac
done

if [[ ${#args[@]} -ne 2 ]]; then
  usage
  exit 1
fi

issue_url="${args[0]}"
status_name="${args[1]}"

fail() {
  jq -n --arg err "$1" '{ok:false, error:$err}'
  exit 1
}

if [[ "$issue_url" =~ github\.com/([^/]+)/([^/]+)/issues/([0-9]+) ]]; then
  owner="${BASH_REMATCH[1]}"
  repo="${BASH_REMATCH[2]}"
  number="${BASH_REMATCH[3]}"
else
  fail "not a GitHub issue URL: $issue_url"
fi

items_json=$(gh api graphql -f query='
  query($owner:String!, $repo:String!, $num:Int!) {
    repository(owner:$owner, name:$repo) {
      issue(number:$num) {
        projectItems(first:10) {
          nodes { id project { id title } }
        }
      }
    }
  }' -F owner="$owner" -F repo="$repo" -F num="$number" \
  --jq '.data.repository.issue.projectItems.nodes') || fail "could not read project items for $issue_url"

count=$(echo "$items_json" | jq 'length')
if [[ "$count" -eq 0 ]]; then
  fail "issue is not on any project"
fi

if [[ -n "$project_filter" ]]; then
  item=$(echo "$items_json" | jq -c --arg t "$project_filter" '[.[] | select(.project.title == $t)] | .[0]')
  if [[ "$item" == "null" ]]; then
    titles=$(echo "$items_json" | jq -r '[.[].project.title] | join(", ")')
    fail "no project named \"$project_filter\" on this issue (found: $titles)"
  fi
elif [[ "$count" -gt 1 ]]; then
  titles=$(echo "$items_json" | jq -r '[.[].project.title] | join(", ")')
  fail "issue is on $count projects: $titles. Pass --project \"<title>\"."
else
  item=$(echo "$items_json" | jq -c '.[0]')
fi

item_id=$(echo "$item" | jq -r '.id')
project_id=$(echo "$item" | jq -r '.project.id')
project_title=$(echo "$item" | jq -r '.project.title')

field_json=$(gh api graphql -f query='
  query($projectId:ID!) {
    node(id:$projectId) {
      ... on ProjectV2 {
        field(name:"Status") {
          ... on ProjectV2SingleSelectField { id options { id name } }
        }
      }
    }
  }' -F projectId="$project_id" --jq '.data.node.field') || fail "could not read the Status field on \"$project_title\""

if [[ "$field_json" == "null" ]]; then
  fail "project \"$project_title\" has no single-select field named Status"
fi

field_id=$(echo "$field_json" | jq -r '.id')
option_id=$(echo "$field_json" | jq -r --arg n "$status_name" '.options[] | select(.name == $n) | .id')

if [[ -z "$option_id" ]]; then
  options=$(echo "$field_json" | jq -r '[.options[].name] | join(", ")')
  fail "no Status option named \"$status_name\" on \"$project_title\" (found: $options)"
fi

if [[ "$dry_run" == true ]]; then
  jq -n --arg p "$project_title" --arg s "$status_name" '{ok:true, project:$p, status:$s, dry_run:true}'
  exit 0
fi

gh api graphql -f query='
  mutation($projectId:ID!, $itemId:ID!, $fieldId:ID!, $optionId:String!) {
    updateProjectV2ItemFieldValue(input:{
      projectId:$projectId, itemId:$itemId, fieldId:$fieldId,
      value:{ singleSelectOptionId:$optionId }
    }) { projectV2Item { id } }
  }' -F projectId="$project_id" -F itemId="$item_id" -F fieldId="$field_id" -F optionId="$option_id" \
  >/dev/null || fail "mutation failed"

jq -n --arg p "$project_title" --arg s "$status_name" '{ok:true, project:$p, status:$s}'
