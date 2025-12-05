---
globs: ["**/openapi.*", "**/swagger.*", "**/api/**", "**/routes/**"]
---

# API Design

## REST Conventions

### HTTP Methods
| Method | Purpose | Idempotent | Body |
|--------|---------|------------|------|
| GET | Read resource | Yes | No |
| POST | Create resource | No | Yes |
| PUT | Replace resource | Yes | Yes |
| PATCH | Update resource | No | Yes |
| DELETE | Remove resource | Yes | No |

### URL Patterns
```
GET    /users              # List users
GET    /users/:id          # Get user
POST   /users              # Create user
PUT    /users/:id          # Replace user
PATCH  /users/:id          # Update user
DELETE /users/:id          # Delete user

# Nested resources
GET    /users/:id/posts    # User's posts
POST   /users/:id/posts    # Create user's post

# Actions (when CRUD doesn't fit)
POST   /users/:id/activate
POST   /orders/:id/cancel
```

### Query Parameters
```
GET /users?page=1&limit=20           # Pagination
GET /users?sort=name&order=asc       # Sorting
GET /users?filter[status]=active     # Filtering
GET /users?include=posts,comments    # Includes
GET /users?fields=id,name,email      # Sparse fields
```

## Response Format

### Success
```json
{
  "data": { "id": 1, "name": "John" },
  "meta": { "requestId": "abc123" }
}

// List
{
  "data": [...],
  "meta": {
    "total": 100,
    "page": 1,
    "limit": 20
  }
}
```

### Errors
```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Invalid input",
    "details": [
      { "field": "email", "message": "Invalid format" }
    ]
  }
}
```

### Status Codes
| Code | Use |
|------|-----|
| 200 | Success |
| 201 | Created |
| 204 | No Content (DELETE) |
| 400 | Bad Request |
| 401 | Unauthorized |
| 403 | Forbidden |
| 404 | Not Found |
| 409 | Conflict |
| 422 | Validation Error |
| 429 | Rate Limited |
| 500 | Server Error |

## Validation

### Input Schema
```typescript
const createUserSchema = z.object({
  email: z.string().email(),
  name: z.string().min(1).max(100),
  role: z.enum(["user", "admin"]).default("user"),
});
```

### Request Validation
```typescript
app.post("/users", validate(createUserSchema), async (req, res) => {
  // req.body is typed and validated
});
```

## Versioning
```
# URL prefix (recommended)
/api/v1/users

# Header
Accept: application/vnd.api+json;version=1
```

## Rate Limiting Headers
```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1640000000
```

## OpenAPI Spec
```yaml
openapi: 3.1.0
paths:
  /users:
    get:
      summary: List users
      parameters:
        - name: page
          in: query
          schema:
            type: integer
            default: 1
      responses:
        '200':
          description: Success
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/UserList'
```
