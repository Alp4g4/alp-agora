# Migrations with goose

A migration is a versioned change to the schema, applied once, in order, to every database: the developer's, CI's, and production's. The migrations folder of the engine, `internal/infrastructure/<engine>/migrations/`, is the history of the schema and its only source: sqlc reads it to generate code (`queries.md`), and the tables it creates follow `schema.md`.

The tool is **goose**, used with SQL files only. goose creates every migration file, keeps the up and down steps in one file, runs each file in a transaction, and refuses a migration that arrives out of order. It is pinned in `go.mod` as a Go tool and run from the Makefile.

- [Layout](#layout)
- [Must contain](#must-contain)
- [Must never contain](#must-never-contain)
- [Design rules](#design-rules)
- [Quick check](#quick-check)

## Layout

```
Makefile                                                    # migrate-* targets, below
internal/infrastructure/postgres/
└── migrations/                                             # SQL of this engine only
    ├── 20261101090000_create_user_account.sql
    ├── 20261101090100_create_customer_order.sql
    ├── 20261102090000_add_user_account_display_name.sql
    ├── 20261102090100_backfill_user_account_display_name.sql
    └── 20261103090000_require_user_account_display_name.sql
```

Migrations are written for one engine: the types (`uuid` or `TEXT`), the locks, and the way a column changes all differ. So they live in the package of the engine, next to its queries and its store, and a SQLite project has `internal/infrastructure/sqlite/migrations/` instead.

The version at the start of each name is written by goose (`make migrate-create`), never by hand.

```make
# goose is pinned in go.mod: go get -tool github.com/pressly/goose/v3/cmd/goose@<version>
# It reads GOOSE_DRIVER and GOOSE_DBSTRING from the environment or the .env file.
# The folder of the engine the project uses (internal/infrastructure/sqlite/migrations for SQLite).
MIGRATIONS := internal/infrastructure/postgres/migrations
GOOSE := go tool goose -dir $(MIGRATIONS)

.PHONY: migrate-create migrate-up migrate-down migrate-status migrate-check

migrate-create: ## make migrate-create name=add_user_account_display_name
	@test -n "$(name)" || (echo "usage: make migrate-create name=<verb>_<object>" && exit 1)
	$(GOOSE) create $(name) sql

migrate-up: ## apply every pending migration
	$(GOOSE) up

migrate-down: ## roll back the last migration
	$(GOOSE) down

migrate-status: ## list applied and pending migrations
	$(GOOSE) status

migrate-check: ## up, down to 0, up: what CI runs on a fresh database
	$(GOOSE) up
	$(GOOSE) reset
	$(GOOSE) up
```

A migration file, as goose creates it and filled in:

```sql
-- +goose Up
ALTER TABLE user_account ADD COLUMN display_name TEXT;

-- +goose Down
ALTER TABLE user_account DROP COLUMN display_name;
```

## Must contain

- **A file created by goose**, named after the change: `make migrate-create name=<verb>_<object>`. Never write a migration file, or its version, by hand.
- **An `Up` and a `Down` section** in every file. `Down` undoes `Up` exactly.
- **One change per migration**: one table created (with its indexes), one column added, one backfill.
- **Steps compatible with the running version**: the application that is deployed while the migration runs keeps working.
- **Expand and contract** for every breaking change, spread over several migrations and releases.

## Must never contain

- **Edits to a migration already applied.** Once merged into `main`, a migration is history. Fix it with a new migration.
- **Data changes mixed with schema changes.** A backfill is its own migration.
- **Destructive changes in one step.** No rename, drop, or retype of a column or a table that the running version still uses.
- **Default values**, even to make a `NOT NULL` column pass on existing rows. `schema.md` forbids them: add the column nullable, backfill, then require it.
- **Go migrations** for what SQL can express. A Go migration is code that drifts with the application: keep migrations in SQL.
- **Application code reaching into migrations.** The application never checks the schema version or runs a migration as a side effect of a request.

## Design rules

1. **Create the file with goose, named after the change with a verb.** `make migrate-create name=add_user_account_display_name`. goose writes the version and the empty `Up` and `Down` sections. Verbs: `create_<table>`, `add_<table>_<column>`, `backfill_<table>_<column>`, `require_<table>_<column>` (to `NOT NULL`), `index_<table>_<columns>`, `rename_<table>_<column>`, `drop_<table>_<column>`. The list of files then reads as the history of the schema.
2. **One change per migration.** A migration that fails halfway is easier to understand, fix, and roll back when it does one thing. A new table and its indexes are one change.
3. **`Down` undoes `Up`, in reverse order, and is tested.** CI applies every migration, rolls back to version 0, and applies them again, on every engine the project uses. When data cannot come back (a dropped column), `Down` restores the structure and a comment says the data is lost.
4. **Never edit a merged migration.** Other databases have already applied it, and goose does not run it again: an edit only creates a difference between environments. A migration in an open pull request may still change.
5. **A new migration is always the newest.** goose refuses a migration older than the last one applied (`detected 1 missing (out-of-order) migration`). When a branch is rebased on a `main` that received newer migrations, create the branch's migration again with `make migrate-create`, move its content into the new file, and delete the old one. CI checks that every new file is newer than the newest one on `main`.
6. **One transaction per file.** goose runs each file in a transaction, so a failed migration leaves nothing behind. Use `-- +goose NO TRANSACTION` only when the engine requires it (`CREATE INDEX CONCURRENTLY` in PostgreSQL, a table rebuild in SQLite), with that one statement or procedure alone in its file.
7. **Schema and data apart.** A backfill is its own migration, between the one that adds the column and the one that requires it. It is idempotent (`WHERE display_name IS NULL`), so running it on a partly filled table is safe. A backfill of a large table does not belong in a migration at all: run it in batches as a job, and keep the migration for the schema.
8. **Every migration works with the version already deployed.** Migrations run before the new version of the application starts, while the old version still serves requests. A change is safe in one step only if the old version keeps working:

   | Safe in one step | Needs expand and contract |
   |---|---|
   | create a table | rename a column or a table |
   | add a nullable column | drop a column or a table |
   | add an index | change a column's type |
   | add a foreign key on a new column | make an existing column `NOT NULL` |
   | | add a unique constraint on existing data |

9. **Expand, migrate, contract.** A breaking change is split into steps, each in its own migration and release, so every step is compatible with the previous version. Making a new column required:

   | Step | Migration | Application release |
   |---|---|---|
   | expand | `add_user_account_display_name`: nullable column | the new version writes `display_name` |
   | migrate | `backfill_user_account_display_name`: fill the old rows | |
   | contract | `require_user_account_display_name`: `NOT NULL` | the domain makes the field required |

   Renaming a column follows the same shape: add the new column, write both, backfill, read the new one, then drop the old one. In a ticket pipeline, the technical spec splits such a change into one ticket per step.
10. **The tables follow `schema.md`.** Names, types, constraint names, no defaults, no `CHECK`, indexes ending with `id` for a keyset: a migration is reviewed against `schema.md` as much as against this file.
11. **Migrations run from the Makefile, before the new version starts.** `make migrate-up` applies pending migrations, then the new version is started. The application never migrates on startup on its own: with several instances, they would race, and a failed migration would leave instances crash-looping.
12. **Test against the real engine.** CI runs `make migrate-check` (up, down to 0, up) on a fresh database of each engine, then `sqlc vet` against the migrated schema. Integration tests of the stores run on a database migrated the same way.

## Quick check

Before adding a migration, ask:

1. Does it do one thing, and does its name say what (`<verb>_<object>`)?
2. Does `Down` undo `Up` exactly, and has it been run?
3. Will the version of the application currently deployed still work after `Up`?
4. Is it a rename, a drop, a type change, or a new `NOT NULL` on an existing column? If so, is it one step of an expand and contract?
5. Does any data change sit in the same file as a schema change?
6. Was it created by goose, after the newest migration on `main`?
