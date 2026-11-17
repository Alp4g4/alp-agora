# PostgreSQL

The rules of `schema.md` applied to PostgreSQL.

## Types

| Value | Type | Not |
|---|---|---|
| ID | `uuid`, holding a UUID v7 | `text`, `serial`, `bigserial`, identity |
| timestamp | `timestamptz` | `timestamp`, `timestamp without time zone` |
| date without time (a birthday) | `date` | `timestamptz` at midnight |
| text | `text` | `varchar(255)`, `char(n)` |
| boolean, only when no timestamp fits | `boolean` | `integer` 0/1 |
| integer | `integer`, or `bigint` when it can exceed 2 billion | `numeric` for counts |
| amount | `bigint` in minor units, plus `currency text` | `money`, `real`, `double precision` |
| closed set of values | `text` | `CREATE TYPE ... AS ENUM`, a `CHECK` |
| payload never searched | `jsonb` | `json` |

- **`timestamptz` does not store a time zone.** It stores an instant in UTC and converts on input and output using the session time zone. The application already passes UTC. The Go driver `pgx` still returns values in the machine's local time zone, whatever the session's `TimeZone`: configure it to scan in UTC (see `queries-postgres.md`).
- **Identifiers are at most 63 characters.** Longer names are silently truncated, which matters for constraint names built from several columns.
- **Reserved words** include `user`, `order`, `group`, `table`, `column`, `default`, `limit`, `offset`, `end`. The full list is in the PostgreSQL documentation, appendix "SQL Key Words": any word marked reserved there needs another name.

## Example: user_account

The domain `user.User` of `go-clean-architecture`. `user` is reserved in PostgreSQL, so the table is `user_account`.

```sql
CREATE TABLE user_account (
    id                uuid        NOT NULL,
    email             text        NOT NULL,
    email_verified_at timestamptz,          -- NULL until the email is verified
    password_hash     text        NOT NULL,
    avatar_key        text,                 -- NULL when the user has no avatar
    created_at        timestamptz NOT NULL,
    updated_at        timestamptz NOT NULL,

    CONSTRAINT pk_user_account PRIMARY KEY (id),
    CONSTRAINT uq_user_account_email UNIQUE (email)
);
```

No `DEFAULT` anywhere: the use case sets `id` with `uuid.NewV7()` and both timestamps from its clock.

The unique constraint is already an index, so a lookup by email needs no other index. `ParseEmail` lowercases the email, so the unique constraint is case-insensitive in practice.

## Example: customer_order and order_item

The domain `order.Order` and its `Item`. `order` is reserved, so the root table is `customer_order`.

```sql
CREATE TABLE customer_order (
    id              uuid        NOT NULL,
    user_account_id uuid        NOT NULL,
    status          text        NOT NULL, -- values of order.Status, validated by the domain
    created_at      timestamptz NOT NULL,
    updated_at      timestamptz NOT NULL,

    CONSTRAINT pk_customer_order PRIMARY KEY (id),
    CONSTRAINT fk_customer_order_user_account_id
        -- between two aggregates (Order → User): RESTRICT
        FOREIGN KEY (user_account_id) REFERENCES user_account (id) ON DELETE RESTRICT
);

-- "orders of a user, newest first", paginated: equality column, then the sort
-- columns, ending with id as the keyset does. It also serves the foreign key:
-- user_account_id is its leftmost column.
CREATE INDEX idx_customer_order_user_account_id_created_at_id
    ON customer_order (user_account_id, created_at, id);

CREATE TABLE order_item (
    id                uuid        NOT NULL,
    customer_order_id uuid        NOT NULL,
    product_id        text        NOT NULL,
    quantity          integer     NOT NULL,
    unit_price_minor  bigint      NOT NULL,
    currency          text        NOT NULL,
    created_at        timestamptz NOT NULL,
    updated_at        timestamptz NOT NULL,

    CONSTRAINT pk_order_item PRIMARY KEY (id),
    -- inside the Order aggregate: CASCADE
    CONSTRAINT fk_order_item_customer_order_id
        FOREIGN KEY (customer_order_id) REFERENCES customer_order (id) ON DELETE CASCADE
);

CREATE INDEX idx_order_item_customer_order_id ON order_item (customer_order_id);
```

No `CHECK` on `status`, `quantity`, `unit_price_minor`, or `currency`: `ParseMoney` and `order.Status` own those rules.

## Indexes specific to PostgreSQL

- **Foreign keys are not indexed automatically.** Add the index yourself, or make the foreign key the leftmost column of a composite index, as `idx_customer_order_user_account_id_created_at_id` does.
- **Partial index** for a query that always filters on the same condition: `CREATE INDEX idx_customer_order_pending_created_at ON customer_order (created_at) WHERE status = 'pending';`. It is smaller and faster than a full index.
- **Expression index** for a query on a computed value, such as `lower(name)`. The query must use the same expression. Prefer normalizing the value in the domain, so a plain index is enough.
- **Create indexes concurrently on a table in use** (`CREATE INDEX CONCURRENTLY`), so writes are not blocked. That is a migration concern, see `migrations.md`.
