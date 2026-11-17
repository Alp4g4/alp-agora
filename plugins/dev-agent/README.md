# dev-agent: senior-dev

An agent that takes a tech spec, implements it, verifies it, opens a PR and handles review rounds until you approve. It never merges.

```
agents/senior-dev.md     the agent: dev-agent:senior-dev
hooks/hooks.json         registers the guard on every Bash call
hooks/guard-bash.sh      inside senior-dev only: blocks push to main/master, plain --force, gh pr merge
(validate-tech-spec.sh    comes from the specs plugin: format checker + format doc and example, --help)
```

## What runs where

You prepare the repository: the right clone, up to date, checked out on the tech spec's branch. The branch name must contain the tech spec's `id` (`fnd-111`, `feat/FND-111-healthz`).

The agent then does the rest, in order: validates the tech spec with `validate-tech-spec.sh` and reads its metadata (`id`, `repo`, `base`, `stack`, `type`, `story`, `depends_on`), checks that `origin` is the spec's `repo` and that the current branch contains its `id`, reads the whole file, and does the work. If the spec is invalid or the repository or branch is wrong, it stops and tells you. It never clones, switches branches or rebases.

## One-time setup

1. Install the tools you need: `gh` (logged in with `gh auth login`), `jq`, `git`, and your stack toolchains.
2. **Install the plugin at user scope**, so the agent is available in every repo. The agent works *inside the target repo*, so that the repo's `CLAUDE.md` loads and the checks run on the right code:
   ```
   /plugin install dev-agent --marketplace Alp4g4/alp-agora
   ```
   Install the `specs` plugin too: it holds the tech spec format and its validator (`validate-tech-spec.sh`), which the agent calls.
   ```
   /plugin install specs --marketplace Alp4g4/alp-agora
   ```
   Install the plugins of the stack too (`go`, and `web-design` for `go-ssr`): the agent loads their skills in Step 2.
3. On GitHub, enable **branch protection** on `main`: require a PR and an approval. The hooks are only a guardrail.
4. Add a `CLAUDE.md` to each target repo saying how to run, test and lint it, plus any project-specific conventions.

## Run it

The agent runs without you, in non-interactive mode. From the root of the target repo, on the tech spec's branch:

```sh
claude -p --agent dev-agent:senior-dev --output-format json "implement tech-specs/FND-111.md"
claude -p --agent dev-agent:senior-dev --output-format json "review https://github.com/org/repo/pull/12"   # on the PR's branch
```

Every run ends with one JSON object as the agent's final message (the `result` field of the JSON output, next to `session_id`):

```json
{"status": "need_inputs", "mode": "implement", "id": "FND-111",
 "summary": "Plan written in PLAN.md: ...", "questions": ["Do you approve the plan in PLAN.md?"],
 "plan": "PLAN.md", "pr_url": null, "error": null}
```

| `status`      | Meaning | What you do |
|---------------|---------|-------------|
| `succeeded`   | PR opened (implement) or review round pushed (review): `pr_url` | review the PR |
| `need_inputs` | the agent needs an answer: invalid or unclear tech spec, dependency not merged, plan approval: `questions` | answer by resuming the session |
| `failed`      | the agent can't do the job: wrong repository or branch, missing plugin or skill, stuck: `error` | fix the cause, run it again |

To answer a `need_inputs`, resume the same session:

```sh
claude -p --agent dev-agent:senior-dev --output-format json --resume <session_id> "Plan approved."
```

Tech specs live in the `tech-specs/` folder of each project. Format, the purpose of each field, and an example: `validate-tech-spec.sh --help`. To check a tech spec by hand: `validate-tech-spec.sh tech-specs/FND-111.md`.

The agent never commits `PLAN.md` (where it writes its plan) or anything in `tech-specs/`. Adding `PLAN.md` to the repo's `.gitignore` or `.git/info/exclude` keeps it out of `git status` too.

## Tuning as trust grows

- Remove the "Plan approval" paragraph in `senior-dev.md` to let it run end to end.
- In non-interactive mode nobody can accept a permission prompt: a tool call that needs one is denied. Give the run the permissions it needs on the `claude` command (`--permission-mode acceptEdits` plus `--allowedTools` for `git`, `gh`, `make` and your toolchain, or the repo's `.claude/settings.json`). A `permissionMode` field in the agent's frontmatter would be ignored: plugin agents don't support it.
- Track the number of review rounds per PR. That's your quality metric.
