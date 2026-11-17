# SQLite migrations with goose

The rules of `migrations.md` applied to SQLite, with the `modernc.org/sqlite` driver. The tables are those of `schema-sqlite.md`.

- [Running migrations](#running-migrations)
- [Migrations](#migrations)
- [The table rebuild](#the-table-rebuild)
- [SQLite specifics](#sqlite-specifics)

SQLite's `ALTER TABLE` can add, rename, and drop a column, and nothing else. Making a column `NOT NULL`, changing its type, or adding a constraint rebuilds the table, with the procedure below.

## Running migrations

The Makefile of `migrations.md` runs goose. goose reads the connection from the environment or `.env`, with the connection string of `schema-sqlite.md`:

```
GOOSE_DRIVER=sqlite3
GOOSE_DBSTRING=file:app.db?_pragma=foreign_keys(1)&_time_format=sqlite
```

`PRAGMA foreign_key_check` lists broken references but never fails a migration. After a table rebuild, run it and expect no output, with a Makefile target:

```make
migrate-fk-check: ## after a rebuild: prints nothing when every reference is intact
	sqlite3 app.db "PRAGMA foreign_key_check"
```

## Migrations

### 20261101090000_create_user_account.sql

```sql
-- +goose Up
CREATE TABLE user_account (
    id                TEXT      NOT NULL,
    email             TEXT      NOT NULL,
    email_verified_at TIMESTAMP,
    password_hash     TEXT      NOT NULL,
    avatar_key        TEXT,
    created_at        TIMESTAMP NOT NULL,
    updated_at        TIMESTAMP NOT NULL,

    CONSTRAINT pk_user_account PRIMARY KEY (id),
    CONSTRAINT uq_user_account_email UNIQUE (email)
);

-- +goose Down
DROP TABLE user_account;
```

### 20261101090100_create_customer_order.sql

```sql
-- +goose Up
CREATE TABLE customer_order (
    id              TEXT      NOT NULL,
    user_account_id TEXT      NOT NULL,
    status          TEXT      NOT NULL,
    created_at      TIMESTAMP NOT NULL,
    updated_at      TIMESTAMP NOT NULL,

    CONSTRAINT pk_customer_order PRIMARY KEY (id),
    CONSTRAINT fk_customer_order_user_account_id
        FOREIGN KEY (user_account_id) REFERENCES user_account (id) ON DELETE RESTRICT
);

CREATE INDEX idx_customer_order_user_account_id_created_at_id
    ON customer_order (user_account_id, created_at, id);

-- +goose Down
DROP TABLE customer_order;
```

### Expand and contract: a required display name

#### 20261102090000_add_user_account_display_name.sql

```sql
-- +goose Up
-- expand: nullable first, the running version does not write it yet
ALTER TABLE user_account ADD COLUMN display_name TEXT;

-- +goose Down
ALTER TABLE user_account DROP COLUMN display_name;
```

#### 20261102090100_backfill_user_account_display_name.sql

```sql
-- +goose Up
-- data only, idempotent: the part of the email before the @
UPDATE user_account
SET display_name = substr(email, 1, instr(email, '@') - 1)
WHERE display_name IS NULL;

-- +goose Down
-- nothing to undo: the previous migration's Down drops the column
```

#### 20261103090000_require_user_account_display_name.sql

SQLite cannot add `NOT NULL` to a column: the contract step rebuilds the table.

```sql
-- +goose NO TRANSACTION

-- +goose Up
-- Foreign keys can only be switched off outside a transaction, so this file
-- manages its own. With them on, DROP TABLE would delete every user and
-- break the orders that reference them.
PRAGMA foreign_keys = OFF;

BEGIN;

CREATE TABLE user_account_new (
    id                TEXT      NOT NULL,
    email             TEXT      NOT NULL,
    email_verified_at TIMESTAMP,
    password_hash     TEXT      NOT NULL,
    avatar_key        TEXT,
    created_at        TIMESTAMP NOT NULL,
    updated_at        TIMESTAMP NOT NULL,
    display_name      TEXT      NOT NULL,

    CONSTRAINT pk_user_account PRIMARY KEY (id),
    CONSTRAINT uq_user_account_email UNIQUE (email)
);

INSERT INTO user_account_new (id, email, email_verified_at, password_hash, avatar_key, created_at, updated_at, display_name)
SELECT id, email, email_verified_at, password_hash, avatar_key, created_at, updated_at, display_name
FROM user_account;

DROP TABLE user_account;
ALTER TABLE user_account_new RENAME TO user_account;

COMMIT;

PRAGMA foreign_keys = ON;

-- +goose Down
PRAGMA foreign_keys = OFF;

BEGIN;

CREATE TABLE user_account_old (
    id                TEXT      NOT NULL,
    email             TEXT      NOT NULL,
    email_verified_at TIMESTAMP,
    password_hash     TEXT      NOT NULL,
    avatar_key        TEXT,
    created_at        TIMESTAMP NOT NULL,
    updated_at        TIMESTAMP NOT NULL,
    display_name      TEXT,

    CONSTRAINT pk_user_account PRIMARY KEY (id),
    CONSTRAINT uq_user_account_email UNIQUE (email)
);

INSERT INTO user_account_old (id, email, email_verified_at, password_hash, avatar_key, created_at, updated_at, display_name)
SELECT id, email, email_verified_at, password_hash, avatar_key, created_at, updated_at, display_name
FROM user_account;

DROP TABLE user_account;
ALTER TABLE user_account_old RENAME TO user_account;

COMMIT;

PRAGMA foreign_keys = ON;
```

## The table rebuild

The procedure for every change `ALTER TABLE` cannot make (`NOT NULL`, a type, a constraint):

1. `-- +goose NO TRANSACTION` at the top of the file, alone in its migration.
2. `PRAGMA foreign_keys = OFF`, then `BEGIN`.
3. Create `<table>_new` with the final definition, following `schema.md`.
4. Copy the rows with an `INSERT ... SELECT` that lists every column on both sides.
5. `DROP TABLE <table>`, then `ALTER TABLE <table>_new RENAME TO <table>`. The other tables' foreign keys reference the table by name, so they point at the new one.
6. Recreate the indexes of the table: `DROP TABLE` removed them. (`user_account` has none besides its constraints.)
7. `COMMIT`, then `PRAGMA foreign_keys = ON`. Then run `make migrate-fk-check`.

## SQLite specifics

- **`PRAGMA defer_foreign_keys` is not enough for a rebuild.** `DROP TABLE` with foreign keys on deletes every row first, and the orders referencing them count as violations at `COMMIT`, even after the new table takes the name. Foreign keys must be off.
- **`DROP COLUMN` fails** if the column is in an index, a foreign key, or a unique constraint. Drop the index first, or rebuild the table.
- **No `CONCURRENTLY`.** SQLite has one writer: an index build blocks writes for its duration, which is short on the table sizes SQLite is used for.
