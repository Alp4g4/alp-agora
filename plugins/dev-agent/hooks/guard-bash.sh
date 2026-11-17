#!/bin/bash
# PreToolUse guard for the senior-dev agent.
# Blocks: pushing to main/master, plain force-push, merging PRs.
# This is a guardrail, not a security boundary: also enable branch protection on GitHub.
#
# Registered in hooks/hooks.json, so it runs for every Bash call while the plugin is
# enabled (plugin agents ignore hooks in their frontmatter). It only acts inside the
# senior-dev agent: the hook input names it in agent_type ("dev-agent:senior-dev").
input=$(cat)
case "$(jq -r '.agent_type // empty' <<<"$input")" in
  senior-dev | *:senior-dev) ;;
  *) exit 0 ;;
esac

cmd=$(jq -r '.tool_input.command // empty' <<<"$input")

block() { echo "Blocked by senior-dev guard: $1" >&2; exit 2; }

# git push targeting main/master (e.g. "git push origin main", "git push origin HEAD:main")
if echo "$cmd" | grep -Eq 'git[[:space:]]+push([^|;&]*)[[:space:]:](main|master)([[:space:]]|$|;|&|\|)'; then
  block "pushing to main/master is not allowed. Push your tech spec branch instead."
fi

# force-push without lease (--force-with-lease is allowed)
if echo "$cmd" | grep -Eq 'git[[:space:]]+push' && \
   echo "$cmd" | grep -Eq '(^|[[:space:]])(-f|--force)([[:space:]]|$)'; then
  block "plain force-push is not allowed. Use --force-with-lease if you really need it."
fi

# merging is the human's job
if echo "$cmd" | grep -Eq 'gh[[:space:]]+pr[[:space:]]+merge'; then
  block "merging PRs is reserved for the human reviewer."
fi

exit 0
