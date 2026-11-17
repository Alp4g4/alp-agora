#!/bin/bash
# linear.sh: everything the agent tooling does with Linear.
#
# Usage:
#   linear.sh fetch    <ID> [--out <dir>] [--force]   download the issue as <dir>/<ID>.md (default dir: ./tickets) and validate it
#   linear.sh comments <ID>                           list the issue's comments, oldest first
#   linear.sh comment  <ID> <text>                    add a comment, prefixed with "🤖 **senior-dev (AI)**" ("-" reads stdin)
#   linear.sh status   <ID>                           print the current status
#   linear.sh status   <ID> <status>                  set the status
#
# Statuses: todo | in-progress | in-review | done
#   They map to the Linear states "Todo", "In Progress", "In Review", "Done" of the issue's team
#   (edit state_name() below if your team uses other names).
#   A Linear state outside this list is printed as "other:<state name>".
#
# fetch mapping (see "From Linear" in validate-ticket.sh --help):
#   id           ← issue identifier
#   stack        ← every label "stack:<component>", joined into a list ("go, go-sql")
#   type         ← label "type:bug", or a label "bug" inside a label group named "type"
#   repo / base  ← "repo: …" / "base: …" lines in the description (removed from the body)
#   body         ← "# <title>", a link to the issue, then the description as is
#   An existing file is never overwritten without --force.
#
# Needs: LINEAR_API_KEY (Linear → Settings → Security & access → Personal API keys), curl, jq
set -euo pipefail

usage() { sed -n '4,9p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
die() { echo "linear.sh: $*" >&2; exit 1; }

# Every comment written by this script starts with this header, so the agent's comments are
# distinguishable from the human's (the Linear author is the API key's owner either way).
AI_HEADER="🤖 **senior-dev (AI)**"

state_name() {   # status → Linear state name
  case "$1" in
    backlog)     echo "Backlog" ;;
    todo)        echo "Todo" ;;
    in-progress) echo "In Progress" ;;
    in-review)   echo "In Review" ;;
    done)        echo "Done" ;;
    *)           return 1 ;;
  esac
}

# gql <query> <variables-json> → prints .data, dies on API error
gql() {
  [ -n "${LINEAR_API_KEY:-}" ] || die "LINEAR_API_KEY is not set"
  local resp
  resp=$(curl -sS https://api.linear.app/graphql \
    -H "Content-Type: application/json" \
    -H "Authorization: $LINEAR_API_KEY" \
    -d "$(jq -n --arg q "$1" --argjson v "$2" '{query: $q, variables: $v}')") || die "cannot reach the Linear API"
  [ "$(echo "$resp" | jq 'has("errors")')" = "false" ] || \
    die "Linear API error: $(echo "$resp" | jq -r '[.errors[].message] | join("; ")')"
  echo "$resp" | jq '.data'
}

# issue <ID> → everything we need about the issue, in one request
issue() {
  local data
  data=$(gql 'query($id: String!) { issue(id: $id) {
      id identifier title description url
      state { name }
      team { states { nodes { id name } } }
      labels { nodes { name parent { name } } }
      comments(first: 100) { nodes { body createdAt user { name } } }
    } }' "$(jq -n --arg id "$1" '{id: $id}')") || exit 1
  [ "$(echo "$data" | jq '.issue')" != "null" ] || die "ticket $1 not found"
  echo "$data" | jq '.issue'
}

# ── Subcommands ───────────────────────────────────────────────────────────────

cmd_fetch() {
  local id="$1"; shift
  local out="tickets" force=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --out)   out="${2:?--out needs a folder}"; shift 2 ;;
      --force) force=1; shift ;;
      *) usage ;;
    esac
  done
  local file="$out/$id.md"
  [ -e "$file" ] && [ "$force" = 0 ] && die "$file already exists. Use --force to overwrite it with the current Linear content."

  local data label_of stack type desc repo base body
  data=$(issue "$id") || exit 1
  # label value for a group: "stack:go" → go, or label "go" whose parent group is "stack" → go
  label_of() {
    echo "$data" | jq -r --arg g "$1" '
      [.labels.nodes[]
        | if (.name | ascii_downcase | startswith($g + ":")) then (.name | split(":")[1] | gsub("^\\s+|\\s+$"; ""))
          elif ((.parent.name // "") | ascii_downcase) == $g then .name
          else empty end
      ] | first // ""'
  }
  # every label of the group, joined: a ticket can need several stack components
  labels_of() {
    echo "$data" | jq -r --arg g "$1" '
      [.labels.nodes[]
        | if (.name | ascii_downcase | startswith($g + ":")) then (.name | split(":")[1] | gsub("^\\s+|\\s+$"; ""))
          elif ((.parent.name // "") | ascii_downcase) == $g then .name
          else empty end
      ] | join(", ")'
  }
  stack=$(labels_of stack)
  type=$(label_of type)
  desc=$(echo "$data" | jq -r '.description // ""')
  # Linear stores the description as markdown and auto-links what looks like an email or a URL:
  #   git@github.com:org/api.git → [git@github.com](<mailto:git@github.com>):org/api.git
  # plain_text removes that formatting: [text](link) → text, then <, >, backticks, \ escapes, spaces.
  plain_text() {
    sed -E -e 's/\[([^]]*)\]\([^)]*\)/\1/g' -e 's/[<>`\\]//g' -e 's/^[[:space:]]+|[[:space:]]+$//g'
  }
  repo=$(echo "$desc" | sed -nE 's/^[[:space:]]*repo:[[:space:]]*//p' | head -n1 | plain_text)
  base=$(echo "$desc" | sed -nE 's/^[[:space:]]*base:[[:space:]]*//p' | head -n1 | plain_text)
  body=$(echo "$desc" | grep -Ev '^[[:space:]]*(repo|base):' || true)

  mkdir -p "$out"
  {
    echo "---"
    echo "id: $id"
    echo "repo: $repo"
    [ -n "$base" ] && echo "base: $base"
    echo "stack: $stack"
    echo "type: $type"
    echo "---"
    echo
    echo "# $(echo "$data" | jq -r '.title')"
    echo
    echo "Source: $(echo "$data" | jq -r '.url')"
    echo
    echo "$body"
  } > "$file"
  echo "Wrote $file"

  local validator
  validator="$(cd "$(dirname "$0")" && pwd)/validate-ticket.sh"
  if [ -x "$validator" ]; then
    "$validator" "$file" >/dev/null || die "fix the issue in Linear, then re-run with --force."
    echo "Ticket is valid."
  fi
}

cmd_comments() {
  local data
  data=$(issue "$1") || exit 1
  # comments starting with AI_HEADER are shown as written by "senior-dev (AI)", without the header
  echo "$data" | jq -r --arg h "$AI_HEADER" '.comments.nodes | sort_by(.createdAt) |
    if length == 0 then "(no comments)" else
      map(
        (if (.body | startswith($h)) then {author: "senior-dev (AI)", body: (.body | ltrimstr($h) | sub("^\\s+"; ""))}
         else {author: (.user.name // "unknown"), body: .body} end) as $c
        | "--- \($c.author) · \(.createdAt[0:16] | sub("T"; " "))\n\($c.body)"
      ) | join("\n\n")
    end'
}

cmd_comment() {
  local id="$1" text="$2" uuid data url
  [ "$text" = "-" ] && text="$(cat)"
  [ -n "$(echo "$text" | tr -d '[:space:]')" ] || die "empty comment"
  uuid=$(issue "$id" | jq -r '.id') || exit 1
  data=$(gql 'mutation($issueId: String!, $body: String!) {
      commentCreate(input: { issueId: $issueId, body: $body }) { success comment { url } }
    }' "$(jq -n --arg i "$uuid" --arg b "$AI_HEADER"$'\n\n'"$text" '{issueId: $i, body: $b}')") || exit 1
  url=$(echo "$data" | jq -r 'if .commentCreate.success then .commentCreate.comment.url else empty end')
  [ -n "$url" ] || die "comment not created on $id"
  echo "ok $url"
}

cmd_get_status() {
  local name s
  name=$(issue "$1" | jq -r '.state.name') || exit 1
  for s in backlog todo in-progress in-review done; do
    [ "$(state_name "$s")" = "$name" ] && { echo "$s"; return; }
  done
  echo "other:$name"
}

cmd_set_status() {
  local id="$1" status="$2" target data state_id result
  target=$(state_name "$status") || die "unknown status '$status' (allowed: todo | in-progress | in-review | done)"
  data=$(issue "$id") || exit 1
  state_id=$(echo "$data" | jq -r --arg n "$target" '.team.states.nodes[] | select(.name == $n) | .id' | head -n1)
  [ -n "$state_id" ] || die "the team of $id has no state named '$target' (available: $(echo "$data" | jq -r '[.team.states.nodes[].name] | join(", ")'))"
  result=$(gql 'mutation($id: String!, $stateId: String!) {
      issueUpdate(id: $id, input: { stateId: $stateId }) { success }
    }' "$(jq -n --arg i "$(echo "$data" | jq -r '.id')" --arg s "$state_id" '{id: $i, stateId: $s}')") || exit 1
  [ "$(echo "$result" | jq -r '.issueUpdate.success')" = "true" ] || die "status of $id not updated"
  echo "ok $id → $status"
}

# ── Dispatch ──────────────────────────────────────────────────────────────────

cmd="${1:-}"; id="${2:-}"
case "$cmd" in -h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;; esac
{ [ -z "$cmd" ] || [ -z "$id" ]; } && usage
echo "$id" | grep -Eq '^[A-Z][A-Z0-9]*-[0-9]+$' || die "not a ticket ID: $id"

case "$cmd" in
  fetch)    shift 2; cmd_fetch "$id" "$@" ;;
  comments) [ $# -eq 2 ] || usage; cmd_comments "$id" ;;
  comment)  [ $# -eq 3 ] || usage; cmd_comment "$id" "$3" ;;
  status)
    case $# in
      2) cmd_get_status "$id" ;;
      3) cmd_set_status "$id" "$3" ;;
      *) usage ;;
    esac ;;
  *) usage ;;
esac
