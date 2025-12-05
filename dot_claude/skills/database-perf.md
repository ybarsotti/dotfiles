---
globs: ["**/models/**", "**/repositories/**", "**/db/**", "**/*orm*"]
---

# Database Performance

## N+1 Query Prevention

### The Problem
```python
# BAD: N+1 queries
users = User.objects.all()  # 1 query
for user in users:
    print(user.posts.all())  # N queries
```

### Solutions

#### Eager Loading (Django)
```python
# select_related: ForeignKey, OneToOne
users = User.objects.select_related("profile").all()

# prefetch_related: ManyToMany, reverse ForeignKey
users = User.objects.prefetch_related("posts").all()

# Combined
users = User.objects.select_related("profile").prefetch_related("posts", "comments")
```

#### Eager Loading (SQLAlchemy)
```python
# joinedload: single query with JOIN
users = session.query(User).options(joinedload(User.profile)).all()

# selectinload: separate IN query (better for large sets)
users = session.query(User).options(selectinload(User.posts)).all()
```

#### Eager Loading (Prisma)
```typescript
const users = await prisma.user.findMany({
  include: {
    posts: true,
    profile: true,
  },
});
```

## Bulk Operations

### Batch Inserts
```python
# BAD: N inserts
for item in items:
    Item.objects.create(**item)

# GOOD: 1 insert
Item.objects.bulk_create([Item(**item) for item in items])
```

### Batch Updates
```python
# BAD: N updates
for user in users:
    user.status = "active"
    user.save()

# GOOD: 1 update
User.objects.filter(id__in=user_ids).update(status="active")
```

## Indexing Strategy

### When to Index
- Columns in WHERE clauses
- Columns in JOIN conditions
- Columns in ORDER BY
- Foreign keys

### Index Types
```sql
-- Single column
CREATE INDEX idx_users_email ON users(email);

-- Composite (order matters!)
CREATE INDEX idx_orders_user_date ON orders(user_id, created_at);

-- Partial (PostgreSQL)
CREATE INDEX idx_active_users ON users(email) WHERE status = 'active';

-- Covering
CREATE INDEX idx_users_covering ON users(email) INCLUDE (name, created_at);
```

## Query Optimization

### Use EXPLAIN
```sql
EXPLAIN ANALYZE SELECT * FROM users WHERE email = 'test@example.com';
```

### Avoid SELECT *
```python
# BAD
users = User.objects.all()

# GOOD: Only needed fields
users = User.objects.values("id", "name", "email")
```

### Pagination
```python
# Offset pagination (simple but slow for large offsets)
users = User.objects.all()[offset:offset+limit]

# Cursor pagination (efficient for large datasets)
users = User.objects.filter(id__gt=last_id).order_by("id")[:limit]
```

## Connection Pooling
```python
# Django
DATABASES = {
    'default': {
        'CONN_MAX_AGE': 60,  # Keep connections alive
        'CONN_HEALTH_CHECKS': True,
    }
}

# SQLAlchemy
engine = create_engine(url, pool_size=5, max_overflow=10)
```

## Testing Query Performance
```python
# Django
from django.test.utils import CaptureQueriesContext

def test_no_n_plus_one(self):
    with CaptureQueriesContext(connection) as ctx:
        list(User.objects.prefetch_related("posts").all())
    assert len(ctx) == 2  # 1 for users, 1 for posts
```
