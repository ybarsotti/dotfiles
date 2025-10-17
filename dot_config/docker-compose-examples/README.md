# Docker Compose Examples for Data Engineering & ML

This directory contains Docker Compose configurations for common data engineering and machine learning infrastructure. These examples allow you to quickly spin up development environments without installing heavy services directly on your machine.

## Available Services

### 📊 Databases

#### PostgreSQL (`postgres.yml`)
Relational database for structured data.

```bash
# Start
docker-compose -f postgres.yml up -d

# Connect
psql -h localhost -U postgres -d mydb

# Stop
docker-compose -f postgres.yml down
```

**Ports:** 5432
**Default credentials:** postgres/postgres

---

#### ClickHouse (`clickhouse.yml`)
Fast OLAP database for analytical workloads.

```bash
# Start
docker-compose -f clickhouse.yml up -d

# Connect via CLI
docker exec -it dev-clickhouse clickhouse-client

# Web UI (Play)
open http://localhost:8123/play

# Stop
docker-compose -f clickhouse.yml down
```

**Ports:** 8123 (HTTP), 9000 (Native)
**Default credentials:** default/clickhouse

---

### 🔄 Streaming & Processing

#### Apache Kafka (`kafka.yml`)
Distributed streaming platform with Zookeeper and Kafka UI.

```bash
# Start
docker-compose -f kafka.yml up -d

# Kafka UI
open http://localhost:8080

# Create a topic
docker exec -it dev-kafka kafka-topics --create \
  --bootstrap-server localhost:9092 \
  --topic test-topic --partitions 3 --replication-factor 1

# Produce messages
docker exec -it dev-kafka kafka-console-producer \
  --bootstrap-server localhost:9092 \
  --topic test-topic

# Consume messages
docker exec -it dev-kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic test-topic --from-beginning

# Stop
docker-compose -f kafka.yml down
```

**Ports:** 9092 (Kafka), 8080 (UI), 2181 (Zookeeper)

---

#### Apache Spark (`spark.yml`)
Unified analytics engine with 1 master and 2 workers.

```bash
# Start
docker-compose -f spark.yml up -d

# Spark Master UI
open http://localhost:8080

# Submit a job
docker exec -it dev-spark-master spark-submit \
  --master spark://spark-master:7077 \
  /opt/spark-apps/your-script.py

# PySpark shell
docker exec -it dev-spark-master pyspark \
  --master spark://spark-master:7077

# Stop
docker-compose -f spark.yml down
```

**Ports:** 8080 (Master UI), 8081-8082 (Worker UIs), 7077 (Master)

---

### 🤖 Machine Learning

#### MLflow Tracking Server (`mlflow.yml`)
ML experiment tracking and model registry with PostgreSQL backend.

```bash
# Start
docker-compose -f mlflow.yml up -d

# MLflow UI
open http://localhost:5000

# Track experiments (in Python)
import mlflow
mlflow.set_tracking_uri("http://localhost:5000")

# Stop
docker-compose -f mlflow.yml down
```

**Ports:** 5000 (MLflow UI), 5433 (PostgreSQL)

---

## Usage Tips

### Start Multiple Services

```bash
# Start Kafka and Spark together
docker-compose -f kafka.yml -f spark.yml up -d

# Or create a custom compose file that imports others
```

### Data Persistence

All services use Docker volumes for data persistence. To completely remove data:

```bash
docker-compose -f <service>.yml down -v
```

### Resource Management

Services are configured with reasonable defaults for development. Adjust resources in the compose files:

```yaml
environment:
  - SPARK_WORKER_MEMORY=4G  # Increase worker memory
  - SPARK_WORKER_CORES=4     # Increase worker cores
```

### Network Access

Services can communicate with each other by service name when started together:

```yaml
# Example: Spark connecting to PostgreSQL
POSTGRES_URL: jdbc:postgresql://dev-postgres:5432/mydb
```

---

## Quick Reference

| Service | Container Name | Ports | UI URL |
|---------|---------------|-------|---------|
| PostgreSQL | dev-postgres | 5432 | - |
| ClickHouse | dev-clickhouse | 8123, 9000 | http://localhost:8123/play |
| Kafka | dev-kafka | 9092 | - |
| Kafka UI | dev-kafka-ui | 8080 | http://localhost:8080 |
| Zookeeper | dev-zookeeper | 2181 | - |
| Spark Master | dev-spark-master | 8080, 7077 | http://localhost:8080 |
| Spark Worker 1 | dev-spark-worker-1 | 8081 | http://localhost:8081 |
| Spark Worker 2 | dev-spark-worker-2 | 8082 | http://localhost:8082 |
| MLflow | dev-mlflow-server | 5000 | http://localhost:5000 |
| MLflow DB | dev-mlflow-db | 5433 | - |

---

## Best Practices

1. **Development Only**: These configurations are for local development, not production
2. **Security**: Default credentials should be changed for any non-local usage
3. **Resource Limits**: Monitor Docker resource usage (`docker stats`)
4. **Clean Up**: Regularly remove unused containers and volumes
5. **Backups**: For important development data, backup volumes before cleaning

---

## Troubleshooting

### Port Already in Use
```bash
# Find what's using the port
lsof -i :5432

# Kill the process or change the port in the compose file
```

### Service Won't Start
```bash
# Check logs
docker-compose -f <service>.yml logs -f

# Restart service
docker-compose -f <service>.yml restart <service-name>
```

### Out of Disk Space
```bash
# Clean up Docker system
docker system prune -a --volumes

# Check Docker disk usage
docker system df
```
