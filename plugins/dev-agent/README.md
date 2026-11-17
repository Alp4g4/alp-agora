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

From the root of the target repo, on the tech spec's branch:

```sh
claude --agent dev-agent:senior-dev "implement tech-specs/FND-111.md"
claude --agent dev-agent:senior-dev "review https://github.com/org/repo/pull/12"   # on the PR's branch
```

Tech specs live in the `tech-specs/` folder of each project. Format, the purpose of each field, and an example: `validate-tech-spec.sh --help`. To check a tech spec by hand: `validate-tech-spec.sh tech-specs/FND-111.md`.

Add `PLAN.md` to the repo's `.gitignore` or `.git/info/exclude`: the agent writes its plan there and never commits it.

## Tuning as trust grows

- Remove the "Plan approval" paragraph in `senior-dev.md` to let it run end to end.
- Add `--permission-mode acceptEdits` to the `claude` command to cut down permission prompts. A `permissionMode` field in the agent's frontmatter would be ignored: plugin agents don't support it.
- Track the number of review rounds per PR. That's your quality metric.
