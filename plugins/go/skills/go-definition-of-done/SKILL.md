---
name: go-definition-of-done
description: Defines when a change to a Go project is done - the project's make check target passes (generated sqlc and templ code regenerated, formatting, go vet, the dependency rule of the clean architecture, tests, go.mod tidy, migrations up and down) and the criteria no command can check hold (a test for every behaviour change, generated code committed with its source, a clean diff). Gives the make check template for a project that has none. Use before declaring a Go change done, before opening or approving a pull request, or when setting up the checks of a Go project.
---

# Go definition of done

A change to a Go project is done when **`make check` passes** and **the criteria below hold**. The commands live in the project, in its `Makefile`, so the developer, the agent, and CI run exactly the same checks. This skill gives the gate, a template for a project without one, and what no command can check.

## The gate: `make check`

1. Run `make check` from the root of the repository, and read the whole output. It passes when it exits with 0.
2. If it fails, fix the cause and run it again. The change is done only when it passes.
3. If a check also fails on the base branch, without the change, it is not this change's problem: do not fix it here, report it.
4. Never make it pass by editing the `check` target, skipping a test, or deleting one.

If the project has no `check` target, run the commands of the template below that apply to it, one by one, and report that the target is missing. Do not add the target as part of an unrelated change.

## Template

Keep the blocks the project uses, in this order: generation first, so everything after it checks the code as it will be committed.

```make
.PHONY: check

check: ## everything CI runs: a change is done when this passes
	# sqlc: only with a sqlc.yaml (go-sql)
	sqlc generate
	sqlc vet
	# templ: only with .templ files (go-ssr)
	go tool templ generate
	go tool templ fmt -fail .
	# always
	test -z "$$(gofmt -l .)" || (gofmt -l . && echo "run gofmt -w on the files above" && exit 1)
	go vet ./...
	scripts/check-deps.sh
	go mod tidy -diff
	go test ./...
	# migrations: only with goose (go-sql); needs the database of GOOSE_DBSTRING
	$(MAKE) migrate-check
```

- **`scripts/check-deps.sh`** is the dependency rule check of `go-clean-architecture`, copied into the project's `scripts/` folder, so the project does not depend on where the skill is installed.
- **`go mod tidy -diff`** (Go 1.23 and later) fails when `go.mod` or `go.sum` is not tidy, and prints the difference without changing anything.
- **`migrate-check`** is the target of `migrations.md` in `go-sql`: up, down to 0, up, on a fresh database.
- **CI starts from a clean checkout**, so it adds one line after `make check`: `git diff --exit-code`. Generated code that was regenerated but not committed fails there. Locally, before a commit, the working tree has changes on purpose, so `make check` itself does not run it.

## What no command checks

- **Every behaviour change has a test**, at the level of the part it changes: the domain with plain unit tests, a use case with fakes of its ports, infrastructure against the real technology, delivery with a fake use case (the layer files of `go-clean-architecture`).
- **Generated code is committed with its source.** After `make check`, the regenerated `sqlcgen` and `*_templ.go` files are part of the change, next to the `.sql` or `.templ` file they come from.
- **A migration is a new file.** No migration already merged was edited (`migrations.md` in `go-sql`).
- **The diff holds only the change.** No debug output, no commented-out code, no leftover `TODO`, no unrelated edit or reformatting.

## Report

When declaring the change done, give:

1. The commands run (`make check`, or the template's commands when the target is missing) and their result.
2. Any check that fails on the base branch too, with its output.
3. Whether the `check` target is missing.
