# Docker Compose examples

Local services for development.

Pre-configured Docker Compose files for common data engineering and ML infrastructure are available in `~/.config/docker-compose-examples/`.

## Available Services

| Service | File | Ports | Usage |
|---------|------|-------|-------|
| PostgreSQL | `postgres.yml` | 5432 | `docker-compose -f ~/.config/docker-compose-examples/postgres.yml up -d` |
| Kafka + UI | `kafka.yml` | 9092, 8080 | `docker-compose -f ~/.config/docker-compose-examples/kafka.yml up -d` |
| Spark Cluster | `spark.yml` | 8080, 7077 | `docker-compose -f ~/.config/docker-compose-examples/spark.yml up -d` |
| ClickHouse | `clickhouse.yml` | 8123, 9000 | `docker-compose -f ~/.config/docker-compose-examples/clickhouse.yml up -d` |
| MLflow Server | `mlflow.yml` | 5000 | `docker-compose -f ~/.config/docker-compose-examples/mlflow.yml up -d` |

## Quick Start

```bash
# Navigate to examples directory
cd ~/.config/docker-compose-examples

# Start PostgreSQL
docker-compose -f postgres.yml up -d

# View logs
docker-compose -f postgres.yml logs -f

# Stop service
docker-compose -f postgres.yml down

# Stop and remove volumes (clean slate)
docker-compose -f postgres.yml down -v
```

See `~/.config/docker-compose-examples/README.md` for detailed usage instructions, connection examples, and troubleshooting tips.
