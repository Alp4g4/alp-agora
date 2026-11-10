# SQLite with sqlc and modernc.org/sqlite

The rules of `go-sql-queries` applied to SQLite, with the pure Go driver `modernc.org/sqlite` through `database/sql`. The tables are the `user_account`, `customer_order`, and `order_item` of `sql-schema` (`references/sqlite.md`): not `STRICT`, IDs in `TEXT`, timestamps declared `TIMESTAMP`. Replace `<module>` with the module path of the project.

## Connection

```go
// foreign keys on, and timestamps written in SQLite's format, on every connection
db, err := sql.Open("sqlite", "file:"+path+"?_pragma=foreign_keys(1)&_time_format=sqlite")
```

The path comes from the configuration, passed by `main`.

## sqlc.yaml

SQLite has no UUID type, so the ID columns are mapped by name. sqlc maps `TIMESTAMP` to `time.Time` by itself.

```yaml
version: "2"
sql:
  - engine: sqlite
    schema: migrations
    queries: internal/infrastructure/sqlite/queries
    gen:
      go:
        package: sqlcgen
        out: internal/infrastructure/sqlite/sqlcgen
        # NULL columns become pointers (*time.Time, *string), as in the entity
        emit_pointers_for_null_types: true
        overrides:
          # a column ending in _id that is not a UUID: before the wildcards
          - column: order_item.product_id
            go_type: string
          # IDs: every primary key and every foreign key
          - column: "*.id"
            go_type: github.com/google/uuid.UUID
          - column: "*.*_id"
            go_type: github.com/google/uuid.UUID
          # domain value objects, column by column
          - column: user_account.email
            go_type:
              import: <module>/internal/domain/user
              type: Email
          - column: user_account.password_hash
            go_type:
              import: <module>/internal/domain/user
              type: PasswordHash
```

`"*.*_id"` follows the naming rule of `sql-schema` (a foreign key is `<table>_id`). A column ending in `_id` that does not hold a UUID, such as `order_item.product_id`, needs its own override back to `string`. sqlc applies the first override that matches, so it goes **before** the wildcards:

```yaml
        overrides:
          - column: order_item.product_id
            go_type: string
          - column: "*.id"
          # ...
```

The generated model has the same shape as with PostgreSQL, so the store casts it the same way (`user.User(m)`).

## queries/user_account.sql

The same queries as PostgreSQL. Named parameters work the same way.

```sql
-- name: GetUserAccount :one
SELECT id, email, email_verified_at, password_hash, avatar_key, created_at, updated_at
FROM user_account
WHERE id = @id;

-- name: GetUserAccountByEmail :one
-- uq_user_account_email is the index
SELECT id, email, email_verified_at, password_hash, avatar_key, created_at, updated_at
FROM user_account
WHERE email = @email;

-- name: ListUserAccounts :many
-- keyset on the primary key: a UUID v7 string sorts by creation time
SELECT id, email, email_verified_at, password_hash, avatar_key, created_at, updated_at
FROM user_account
WHERE id < @cursor
ORDER BY id DESC
LIMIT @limit_count;

-- name: CreateUserAccount :exec
INSERT INTO user_account (id, email, email_verified_at, password_hash, avatar_key, created_at, updated_at)
VALUES (@id, @email, sqlc.narg(email_verified_at), @password_hash, sqlc.narg(avatar_key), @created_at, @updated_at);

-- name: UpdateUserAccount :execrows
-- every column but id and created_at: the whole entity is saved
UPDATE user_account
SET email = @email,
    email_verified_at = sqlc.narg(email_verified_at),
    password_hash = @password_hash,
    avatar_key = sqlc.narg(avatar_key),
    updated_at = @updated_at
WHERE id = @id;

-- name: DeleteUserAccount :execrows
DELETE FROM user_account
WHERE id = @id;
```

## queries/customer_order.sql

```sql
-- name: ListCustomerOrdersByUserAccount :many
-- idx_customer_order_user_account_id_created_at_id: equality column, then the sort
-- the pair comparison is written out, so sqlc types each parameter from its column
SELECT id, user_account_id, status, created_at, updated_at
FROM customer_order
WHERE user_account_id = @user_account_id
  AND (created_at < @cursor_created_at
       OR (created_at = @cursor_created_at AND id < @cursor_id))
ORDER BY created_at DESC, id DESC
LIMIT @limit_count;

-- name: ListOrderItemsByCustomerOrders :many
-- the items of several orders in one query: no N+1, bounded by the orders
SELECT id, customer_order_id, product_id, quantity, unit_price_minor, currency, created_at, updated_at
FROM order_item
WHERE customer_order_id IN (sqlc.slice(customer_order_ids));
```

## SQLite specifics

- **`sqlc.slice` instead of `ANY`.** SQLite has no arrays. `sqlc.slice(customer_order_ids)` generates a `[]uuid.UUID` parameter and expands to one placeholder per element at run time. Keep the list bounded (the IDs of one page), since each element is a parameter.
- **The keyset pair is written out.** SQLite supports row values, but sqlc gives every parameter of `(created_at, id) < (@a, @b)` the type of the first column, and SQLite has no cast to `uuid`. `created_at < @a OR (created_at = @a AND id < @b)` types each parameter from its own column, and SQLite still reads the page from `(user_account_id, created_at, id)` with no sort step.
- **Timestamps come back with a zero offset, not in `time.UTC`.** The driver reads `+00:00` as an unnamed fixed zone. The instant is right and `Equal` works, but `==`, `reflect.DeepEqual`, and `Location()` see a different zone. Compare times with `Equal` in tests.
- **Comparing timestamps is comparing text.** It is correct only because every value is written in the same format (`_time_format=sqlite`) and in UTC. A value written another way, by hand or by another tool, breaks the order.
- **The first page** passes `uuid.Max` as the cursor: its string, `ffffffff-ffff-ffff-ffff-ffffffffffff`, sorts after every lowercase UUID.
