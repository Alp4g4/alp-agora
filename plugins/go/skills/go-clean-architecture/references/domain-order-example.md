# Domain Order

Package `order`: an entity with exported fields, a `Money` value object, a status type, and domain errors. `Cancel` holds only the rule (which statuses allow cancellation); the `CancelOrder` use case does the orchestration.

- [order.go](#ordergo): the entity, `Total`, and `Cancel`
- [status.go](#statusgo): the status type
- [money.go](#moneygo): the `Money` value object with `ParseMoney`
- [errors.go](#errorsgo): the domain errors
- [What stays out of this package](#what-stays-out-of-this-package)

## order.go

```go
package order

import (
	"time"
	"uuid"
)

type Order struct {
	ID        uuid.UUID
	UserID    uuid.UUID
	Items     []Item
	Status    Status
	CreatedAt time.Time
	UpdatedAt time.Time
}

type Item struct {
	ProductID string
	Quantity  int
	UnitPrice Money
}

// Total sums the items. It is a business rule, true for every use case.
func (o Order) Total() (Money, error) {
	total := Money{}
	for i, item := range o.Items {
		line := Money{Amount: item.UnitPrice.Amount * int64(item.Quantity), Currency: item.UnitPrice.Currency}
		if i == 0 {
			total = Money{Currency: line.Currency}
		}
		var err error
		if total, err = total.Add(line); err != nil {
			return Money{}, err
		}
	}
	return total, nil
}

// Cancel holds only the rule: a shipped or delivered order cannot be cancelled.
// It does not load, save, refund, or notify: that is the CancelOrder use case.
func (o *Order) Cancel() error {
	switch o.Status {
	case StatusCancelled:
		return ErrOrderAlreadyCancelled
	case StatusShipped, StatusDelivered:
		return ErrOrderNotCancellable
	}
	o.Status = StatusCancelled
	return nil
}
```

## status.go

```go
package order

type Status string

const (
	StatusPending   Status = "pending"
	StatusPaid      Status = "paid"
	StatusShipped   Status = "shipped"
	StatusDelivered Status = "delivered"
	StatusCancelled Status = "cancelled"
)
```

## money.go

```go
package order

// Money is an immutable value object. Amount is in minor units (cents).
type Money struct {
	Amount   int64
	Currency string
}

func ParseMoney(amount int64, currency string) (Money, error) {
	if amount < 0 {
		return Money{}, ErrNegativeAmount
	}
	if len(currency) != 3 {
		return Money{}, ErrInvalidCurrency
	}
	return Money{Amount: amount, Currency: currency}, nil
}

// Add returns a new Money; the receiver is never mutated.
func (m Money) Add(other Money) (Money, error) {
	if m.Currency != other.Currency {
		return Money{}, ErrCurrencyMismatch
	}
	return Money{Amount: m.Amount + other.Amount, Currency: m.Currency}, nil
}
```

## errors.go

```go
package order

import "errors"

var (
	ErrOrderNotCancellable   = errors.New("order cannot be cancelled once shipped")
	ErrOrderAlreadyCancelled = errors.New("order is already cancelled")
	ErrNegativeAmount        = errors.New("amount cannot be negative")
	ErrInvalidCurrency       = errors.New("invalid currency code")
	ErrCurrencyMismatch      = errors.New("currencies do not match")
)
```

## What stays out of this package

- The repository port (`cancelOrderRepository`) and the `paymentRefunder` / `orderNotifier` ports: application layer, declared in the `CancelOrder` use case.
- The `CancelOrder` use case: load the order, call `order.Cancel()`, save it, refund the payment, notify the user.
- Setting a plain field such as a shipping note: the use case assigns it directly, with no `SetNote` method.
- Transport and storage models (`json:` / `db:` tags): outer layers.
