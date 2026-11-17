# PostgreSQL with sqlc and pgx

The rules of `queries.md` applied to PostgreSQL, with the `pgx/v5` driver. The tables are the `user_account`, `customer_order`, and `order_item` of `schema-postgres.md`. Replace `<module>` with the module path of the project.

- [sqlc.yaml](#sqlcyaml)
- [queries/user_account.sql](#queriesuser_accountsql)
- [queries/customer_order.sql](#queriescustomer_ordersql)
- [Using it in the store](#using-it-in-the-store)
- [Read timestamps back in UTC](#read-timestamps-back-in-utc)
- [PostgreSQL specifics](#postgresql-specifics)

## sqlc.yaml

```yaml
version: "2"
sql:
  - engine: postgresql
    schema: internal/infrastructure/postgres/migrations
    queries: internal/infrastructure/postgres/queries
    gen:
      go:
        package: sqlcgen
        out: internal/infrastructure/postgres/sqlcgen
        sql_package: pgx/v5
        # NULL columns become pointers (*time.Time, *string), as in the entity
        emit_pointers_for_null_types: true
        overrides:
          # engine types
          - db_type: uuid
            go_type: uuid.UUID
          - db_type: timestamptz
            go_type: time.Time
          - db_type: timestamptz
            nullable: true
            go_type:
              type: time.Time
              pointer: true
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

The generated model then has exactly the shape of `user.User`:

```go
// sqlcgen/models.go (generated)
type UserAccount struct {
	ID              uuid.UUID
	Email           user.Email
	EmailVerifiedAt *time.Time
	PasswordHash    user.PasswordHash
	AvatarKey       *string
	CreatedAt       time.Time
	UpdatedAt       time.Time
}
```

## queries/user_account.sql

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
-- keyset on the primary key: UUID v7 sorts by creation time
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

-- name: ExistsUserAccountByEmail :one
-- uq_user_account_email is the index
SELECT EXISTS (
    SELECT 1 FROM user_account WHERE email = @email
);
```

## queries/customer_order.sql

```sql
-- name: ListCustomerOrdersByUserAccount :many
-- idx_customer_order_user_account_id_created_at_id: equality column, then the sort
-- each cursor parameter is cast: sqlc would type both as the first column
SELECT id, user_account_id, status, created_at, updated_at
FROM customer_order
WHERE user_account_id = @user_account_id
  AND (created_at, id) < (@cursor_created_at::timestamptz, @cursor_id::uuid)
ORDER BY created_at DESC, id DESC
LIMIT @limit_count;

-- name: ListOrderItemsByCustomerOrders :many
-- the items of several orders in one query: no N+1, bounded by the orders
SELECT id, customer_order_id, product_id, quantity, unit_price_minor, currency, created_at, updated_at
FROM order_item
WHERE customer_order_id = ANY(@customer_order_ids::uuid[]);

-- name: ListCustomerOrdersWithEmail :many
-- a join: every table aliased, every column prefixed, the result is a Row struct
SELECT co.id, co.status, co.created_at, u.email
FROM customer_order co
JOIN user_account u ON u.id = co.user_account_id
WHERE co.status = @status
ORDER BY co.created_at DESC, co.id DESC
LIMIT @limit_count;
```

`ListCustomerOrdersWithEmail` filters on `status`, which no index covers. In a conversation, ask before adding `idx_customer_order_status_created_at_id` on `(status, created_at, id)`. In a pipeline, add it in the migration and list it in the pull request.

## Using it in the store

The store casts the model and never returns it:

```go
func (s *UserStore) GetUser(ctx context.Context, id uuid.UUID) (user.User, error) {
	m, err := s.queries.GetUserAccount(ctx, id)
	if err != nil {
		return user.User{}, err // translated into an application error by the store, see infrastructure.md in go-clean-architecture
	}

	return user.User(m), nil // same fields, same order, same types: a cast
}
```

## Read timestamps back in UTC

pgx returns a `timestamptz` in the machine's local time zone. The instant is right (`Equal` is true), but the `Location` is not UTC, and the domain expects UTC. Register the codec with `ScanLocation: time.UTC` on every connection:

```go
// scanTimesInUTC makes pgx return timestamptz values in UTC instead of the
// machine's local time zone.
func scanTimesInUTC(_ context.Context, conn *pgx.Conn) error {
	conn.TypeMap().RegisterType(&pgtype.Type{
		Name:  "timestamptz",
		OID:   pgtype.TimestamptzOID,
		Codec: &pgtype.TimestamptzCodec{ScanLocation: time.UTC},
	})
	return nil
}

// where the pool is built (configuration comes from main)
cfg, err := pgxpool.ParseConfig(databaseURL)
cfg.AfterConnect = scanTimesInUTC
pool, err := pgxpool.NewWithConfig(ctx, cfg)
```

## PostgreSQL specifics

- **Parameter types.** sqlc infers a parameter's type from the column it is compared to. When it cannot (an array, an expression), cast it in the query: `@customer_order_ids::uuid[]`.
- **Row comparison** `(created_at, id) < (@a::timestamptz, @b::uuid)`: sqlc gives every parameter of a row comparison the type of its first column (`CursorID time.Time`), so cast each one. PostgreSQL then uses the comparison directly as an index condition on `(user_account_id, created_at, id)`, with no sort step.
- **`ANY` with an array** replaces `IN` for a list of IDs. One parameter, any length, one prepared plan.
