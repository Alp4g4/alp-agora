# PostgreSQL migrations with goose

The rules of `sql-migrations` applied to PostgreSQL. The tables are those of `sql-schema` (`references/postgres.md`).

## Running migrations

The Makefile of `sql-migrations` runs goose. goose reads the connection from the environment or `.env`:

```
GOOSE_DRIVER=postgres
GOOSE_DBSTRING=postgres://app:secret@localhost:5432/app?sslmode=disable&lock_timeout=5s
```

`lock_timeout` in the connection string applies to every statement of the migration. An `ALTER TABLE` waits for the locks of running queries, and every query that arrives after it waits behind it: the application stalls. With a timeout, the migration fails fast instead, and can be retried at a quieter time.

## Migrations

### 20261101090000_create_user_account.sql

```sql
-- +goose Up
CREATE TABLE user_account (
    id                uuid        NOT NULL,
    email             text        NOT NULL,
    email_verified_at timestamptz,
    password_hash     text        NOT NULL,
    avatar_key        text,
    created_at        timestamptz NOT NULL,
    updated_at        timestamptz NOT NULL,

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
    id              uuid        NOT NULL,
    user_account_id uuid        NOT NULL,
    status          text        NOT NULL,
    created_at      timestamptz NOT NULL,
    updated_at      timestamptz NOT NULL,

    CONSTRAINT pk_customer_order PRIMARY KEY (id),
    CONSTRAINT fk_customer_order_user_account_id
        FOREIGN KEY (user_account_id) REFERENCES user_account (id) ON DELETE RESTRICT
);

-- a new, empty table: a plain CREATE INDEX in the same migration is fine
CREATE INDEX idx_customer_order_user_account_id_created_at_id
    ON customer_order (user_account_id, created_at, id);

-- +goose Down
DROP TABLE customer_order;
```

### Expand and contract: a required display name

Three migrations, released one after the other.

#### 20261102090000_add_user_account_display_name.sql

```sql
-- +goose Up
-- expand: nullable first, the running version does not write it yet
ALTER TABLE user_account ADD COLUMN display_name text;

-- +goose Down
ALTER TABLE user_account DROP COLUMN display_name;
```

#### 20261102090100_backfill_user_account_display_name.sql

```sql
-- +goose Up
-- data only, idempotent: the part of the email before the @
UPDATE user_account
SET display_name = split_part(email, '@', 1)
WHERE display_name IS NULL;

-- +goose Down
-- nothing to undo: the previous migration's Down drops the column
```

#### 20261103090000_require_user_account_display_name.sql

```sql
-- +goose Up
-- contract: every row has a value, and the deployed version writes it
ALTER TABLE user_account ALTER COLUMN display_name SET NOT NULL;

-- +goose Down
ALTER TABLE user_account ALTER COLUMN display_name DROP NOT NULL;
```

### 20261103090100_index_customer_order_status_created_at_id.sql

An index on a table already in use:

```sql
-- +goose NO TRANSACTION

-- +goose Up
-- CONCURRENTLY does not block writes, and cannot run inside a transaction
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_customer_order_status_created_at_id
    ON customer_order (status, created_at, id);

-- +goose Down
DROP INDEX CONCURRENTLY IF EXISTS idx_customer_order_status_created_at_id;
```

## PostgreSQL specifics

- **`CREATE INDEX` locks writes; `CONCURRENTLY` does not.** On an existing table, always `CREATE INDEX CONCURRENTLY`, in a `NO TRANSACTION` file of its own. A concurrent build that fails leaves an `INVALID` index: `IF NOT EXISTS` would then skip it, so drop it and run the migration again. A plain `CREATE INDEX` is fine on a table created in the same migration.
- **Adding a nullable column is instant.** No default means no rewrite of the table.
- **`SET NOT NULL` scans the whole table** under an exclusive lock. On a large table, run the contract step at a quiet time, with `lock_timeout` set.
- **A foreign key on an existing column of a large table** is added in two migrations: `ADD CONSTRAINT ... NOT VALID` (instant, checks new rows only), then `VALIDATE CONSTRAINT` (checks old rows without blocking writes).
- **Changing a column's type** rewrites the table under an exclusive lock. Prefer expand and contract: a new column of the new type, a backfill, then drop the old one.
