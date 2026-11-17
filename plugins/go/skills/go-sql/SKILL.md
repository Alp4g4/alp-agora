---
name: go-sql
description: Designs the SQL layer of a Go project on PostgreSQL or SQLite, covering the schema (tables, columns, types, primary keys as UUID v7, timestamps with time zone, constraints, foreign keys, indexes), the migrations written and run with goose (one change per migration, up and down, expand and contract for breaking changes), and the queries written with sqlc (annotated .sql files, named parameters, overrides to domain types, keyset pagination). Use when creating or reviewing a table, a column, an index, a constraint, a migration, a SQL query, or sqlc.yaml, when planning a schema change that renames, removes, or retypes a column, or when writing the store that calls the generated code.
---

# Go SQL

The SQL layer of a Go project is three things, in this order:

1. **The schema** (`schema.md`): the rules every table follows. It stores what the application decided and decides nothing itself.
2. **The migrations** (`migrations.md`): the versioned changes, written and run with goose, that create and change those tables. They are written for one engine, so they live with its code, in `internal/infrastructure/<engine>/migrations/`, the only source of the schema.
3. **The queries** (`queries.md`): the `.sql` files sqlc turns into Go code, checked against the migrations. A store in the infrastructure layer calls the generated code and casts its result to the domain entity (`infrastructure.md` in `go-clean-architecture`).

## Supported engines

**PostgreSQL** (driver `pgx/v5`) and **SQLite** (driver `modernc.org/sqlite`, through `database/sql`) only. The rules files apply to both. What differs per engine is in its reference file. Other engines (MySQL, MariaDB, SQL Server, Oracle, ...) are not supported: do not apply these rules to them as they are.

## Read the files of the task

Read the rules file of the topic, then the reference of the engine the project uses (the `engine` of `sqlc.yaml`, or the driver in `go.mod`):

| Working on | Rules | PostgreSQL | SQLite |
|---|---|---|---|
| a table, a column, a type, an index, a constraint | `schema.md` | `references/schema-postgres.md` | `references/schema-sqlite.md` |
| a migration, a schema change, goose, the `migrate-*` Makefile targets | `migrations.md` | `references/migrations-postgres.md` | `references/migrations-sqlite.md` |
| a query, `sqlc.yaml`, the store calling the generated code | `queries.md` | `references/queries-postgres.md` | `references/queries-sqlite.md` |

## Adding a table

Copy this checklist and check off each step:

```
- [ ] 1. Schema: design the table following schema.md and the engine's schema reference
- [ ] 2. Migration: make migrate-create name=create_<table>, then write Up and Down (migrations.md)
- [ ] 3. Queries: one .sql file for the table, overrides in sqlc.yaml, sqlc generate (queries.md)
- [ ] 4. Store: call the generated code, cast to the entity, translate the errors (infrastructure.md in go-clean-architecture)
- [ ] 5. Verify: make migrate-check, sqlc vet, sqlc generate then git diff --exit-code, go test ./...
```

If step 5 fails, fix the cause and run every command again. The table is done only when they all pass.
