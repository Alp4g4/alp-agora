# dev-agent: senior-dev

An agent that takes a technical ticket, implements it, verifies it, opens a PR and handles review rounds until you approve. It never merges.

```
agents/senior-dev.md     the agent: dev-agent:senior-dev
hooks/hooks.json         registers the guard on every Bash call
hooks/guard-bash.sh      inside senior-dev only: blocks push to main/master, plain --force, gh pr merge
bin/dev                  entry point: implement <file> | review
bin/setup-repo.sh        checks the repo, fetches, creates the worktree of branch <id lowercase>
(validate-tech-spec.sh    comes from the specs plugin: format checker + format doc and example, --help)
```

## What runs where

`bin/dev implement` does everything a script can do, in order, before the agent starts: validate the ticket format, set up the worktree of the branch `<id lowercase>`, then start the agent inside that worktree with the ticket's metadata (`id`, `repo`, `base`, `stack`, `type`, `story`, `depends_on`, worktree state) in its first message. The agent never validates or sets up anything: it reads the content, judges it, and does the work. Without that metadata block it refuses to start.

## One-time setup

1. Install the tools you need: `gh` (logged in with `gh auth login`), `jq`, `git`, and your stack toolchains.
2. **Install the plugin at user scope**, so the agent is available in every repo. The agent works *inside the target repo*, so that the repo's `CLAUDE.md` loads and the checks run on the right code:
   ```
   /plugin install dev-agent --marketplace Alp4g4/alp-agora
   ```
   Install the `specs` plugin too: it holds the tech spec format and its validator (`validate-tech-spec.sh`), which the agent and `bin/dev` call.
   ```
   /plugin install specs --marketplace Alp4g4/alp-agora
   ```
   Install the plugins of the stack too (`go`, and `web-design` for `go-ssr`): the agent loads their skills in Step 2.
3. On GitHub, enable **branch protection** on `main`: require a PR and an approval. The hooks are only a guardrail.
4. Add a `CLAUDE.md` to each target repo saying how to run, test and lint it, plus any project-specific conventions.

## Phase 1: run it by hand (no MCP)

Run `bin/dev` from your terminal: add `plugins/dev-agent/bin/` of your alp-agora clone to your PATH (the plugin puts `bin/` on the agent's PATH, not on your shell's), then:

```sh
dev implement tech-specs/PROJ-142.md      # run from the project's clone; validates the ticket, starts the agent
dev review https://github.com/org/repo/pull/12   # run from the target repo
```

Tech specs live in the `tech-specs/` folder of each project. Format, the purpose of each field, and an example: `validate-tech-spec.sh --help`. To check a ticket by hand: `validate-tech-spec.sh tech-specs/PROJ-142.md`. The validator lives in `plugins/specs/bin/`; `bin/dev` finds it there in a marketplace clone, otherwise put it on your PATH.

## Tuning as trust grows

- Remove the "Plan approval" paragraph in `senior-dev.md` to let it run end to end.
- Add `--permission-mode acceptEdits` to the `claude` calls in `bin/dev` to cut down permission prompts. A `permissionMode` field in the agent's frontmatter would be ignored: plugin agents don't support it.
- Track the number of review rounds per PR. That's your quality metric.
