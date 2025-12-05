---
globs: ["**/Dockerfile*", "**/docker-compose*.yml", "**/compose*.yml", "**/.dockerignore"]
---

# Docker Operations

## Dockerfile Best Practices

### Multi-Stage Builds
```dockerfile
# Build stage
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Production stage
FROM node:20-alpine AS runner
WORKDIR /app
RUN addgroup -g 1001 -S nodejs && adduser -S nextjs -u 1001
COPY --from=builder --chown=nextjs:nodejs /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
USER nextjs
EXPOSE 3000
CMD ["node", "dist/index.js"]
```

### Layer Caching
```dockerfile
# BAD: Bust cache on any change
COPY . .
RUN npm install

# GOOD: Cache dependencies
COPY package*.json ./
RUN npm ci
COPY . .
```

### Minimize Image Size
```dockerfile
# Use slim/alpine base
FROM python:3.12-slim

# Remove cache in same layer
RUN apt-get update && apt-get install -y \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Use .dockerignore
```

### Security
```dockerfile
# Run as non-root
RUN useradd -r -u 1001 appuser
USER appuser

# Don't store secrets
# Use build args for non-sensitive config only
ARG APP_VERSION
ENV APP_VERSION=$APP_VERSION

# Scan for vulnerabilities
# docker scout cve <image>
```

## Docker Compose

### Service Definition
```yaml
services:
  api:
    build:
      context: .
      dockerfile: Dockerfile
      target: runner
    ports:
      - "3000:3000"
    environment:
      - DATABASE_URL=postgres://db:5432/app
    depends_on:
      db:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    deploy:
      resources:
        limits:
          memory: 512M
```

### Development vs Production
```yaml
# compose.yml (base)
services:
  api:
    image: myapp

# compose.override.yml (dev - auto-loaded)
services:
  api:
    build: .
    volumes:
      - .:/app
    command: npm run dev

# compose.prod.yml
services:
  api:
    image: myapp:${VERSION}
    restart: always
```

### Networking
```yaml
services:
  api:
    networks:
      - frontend
      - backend

  db:
    networks:
      - backend

networks:
  frontend:
  backend:
    internal: true  # No external access
```

## .dockerignore
```
node_modules
.git
.env*
*.log
Dockerfile*
docker-compose*
.dockerignore
README.md
tests/
coverage/
.github/
```

## Common Commands
```bash
# Build with no cache
docker build --no-cache -t myapp .

# Prune unused resources
docker system prune -af

# View logs
docker compose logs -f api

# Execute in running container
docker compose exec api sh

# Copy files
docker cp container:/path/file ./local
```
