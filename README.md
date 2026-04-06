# infra-local-shared

Shared local infrastructure for the TCC project. Runs Redis, InfluxDB, and HashiCorp Vault via Docker Compose.

## Quick Start

```bash
cp .env.example .env
# fill in secret values in .env
docker compose up -d
```

To recreate init containers after config changes:

```bash
docker compose up -d --force-recreate
```

---

## Environment Variables (`.env`)

Vault secrets are defined in `.env` and injected into the `vault-init` container at startup. `.env` is gitignored — never commit it.

| File            | Purpose                              | Committed |
|-----------------|--------------------------------------|-----------|
| `.env.example`  | Empty placeholders — source of truth | Yes       |
| `.env`          | Real secret values                   | No        |

**Setup:**

```bash
cp .env.example .env
# fill in values
```

**Current variables:**

| Variable                        | Vault path             | Key              |
|---------------------------------|------------------------|------------------|
| `LIVE_MS_JAVA_OLHOVIVO_TOKEN`   | `secret/live-ms-java`  | `olhovivo.token` |

> When adding a new microservice, add its variables here and follow the steps in [Adding Secrets for a New Microservice](#adding-secrets-for-a-new-microservice).

---

## Services

| Service  | Container         | Port | Purpose                           |
|----------|-------------------|------|-----------------------------------|
| Redis    | `shared-redis`    | 6379 | Service bus between microservices |
| InfluxDB | `shared-influxdb` | 8086 | Time-series metrics/events        |
| Vault    | `shared-vault`    | 8200 | Secret management                 |

---

## Redis

Redis runs with AOF persistence (survives crashes between RDB snapshots). Data is stored in `./data/redis/`.

### Connect

```bash
# CLI (from host)
redis-cli -h localhost -p 6379

# From another container on shared-infra-network
redis-cli -h shared-redis -p 6379
```

### Basic Operations

```bash
# Set a key
SET my-key "value"

# Get a key
GET my-key

# Publish a message (service bus pattern)
PUBLISH my-channel "payload"

# Subscribe to a channel
SUBSCRIBE my-channel

# List all keys
KEYS *

# Check memory usage
INFO memory
```

### Logs

```bash
docker compose logs -f redis
```

---

## InfluxDB

- **URL:** http://localhost:8086
- **Org:** `tcc-org`
- **Admin token:** `tcc-local-super-secret-token`
- **Username:** `admin` / **Password:** `admin123`

Data is stored in `./data/influxdb/`.

### Web UI Walkthrough

1. Open http://localhost:8086
2. Log in with `admin` / `admin123`

**Explore data:**
- Go to **Data Explorer** (left sidebar, chart icon)
- Select bucket → measurement → fields → time range → **Submit**

**Write data manually:**
- Go to **Load Data → Buckets → [bucket name] → Add Data → Line Protocol**
- Paste line protocol and click **Write Data**

**Create a dashboard:**
- Go to **Dashboards → + Create Dashboard**
- Add cells, pick bucket and measurement

**Manage tokens:**
- Go to **Load Data → API Tokens**
- Create scoped tokens per microservice (read/write on specific buckets)

### Buckets

| Bucket        | Retention | Purpose                  |
|---------------|-----------|--------------------------|
| `events`      | infinite  | Primary/default bucket   |
| `live-events` | 30 days   | Live microservice events |
| `metrics`     | 7 days    | General metrics          |

### Adding a New Bucket

Edit the `influxdb-init` entrypoint in `docker-compose.yml`:

```yaml
entrypoint: >
  sh -c "
    influx bucket create --name live-events   --org tcc-org --retention 30d &&
    influx bucket create --name metrics       --org tcc-org --retention 7d  &&
    influx bucket create --name my-new-bucket --org tcc-org --retention 90d
  "
```

Then recreate the init container:

```bash
docker compose up -d --force-recreate influxdb-init
```

> Retention `0` means infinite. Values like `24h`, `7d`, `30d`, `90d` are valid.

### Write Data (CLI / HTTP)

```bash
# Via curl (line protocol)
curl -s -o /dev/null -w "%{http_code}" \
  -X POST "http://localhost:8086/api/v2/write?org=tcc-org&bucket=metrics&precision=s" \
  -H "Authorization: Token tcc-local-super-secret-token" \
  -H "Content-Type: text/plain" \
  --data-raw "cpu_usage,host=server01 value=42.5 $(date +%s)"
```

### Logs

```bash
docker compose logs -f influxdb
docker compose logs -f influxdb-init
```

---

## HashiCorp Vault

- **URL:** http://localhost:8200
- **Root token:** `tcc-local-root-token`

Vault runs in **dev mode** — all secrets are in-memory and reset on container restart. For local development only.

### Connect

```bash
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=tcc-local-root-token
```

### Read / Write Secrets

```bash
# Read all secrets for a microservice
vault kv get secret/live-ms-java

# Read a single field
vault kv get -field=olhovivo.token secret/live-ms-java

# Write / update secrets
vault kv put secret/live-ms-java key1=value1 key2=value2

# List all secret paths
vault kv list secret/
```

### Adding Secrets for a New Microservice

Secrets are kept out of the repository using a `.env` file (gitignored). The convention is `secret/<microservice-name>`.

**Step 1** — add variables to `.env` and `.env.example`:

```env
# .env (real values — never commit)
MY_NEW_MS_DB_PASSWORD=supersecret
MY_NEW_MS_API_KEY=abc123

# .env.example (empty placeholders — commit this)
MY_NEW_MS_DB_PASSWORD=
MY_NEW_MS_API_KEY=
```

**Step 2** — reference them in the `vault-init` entrypoint in `docker-compose.yml`:

```yaml
entrypoint: >
  sh -c "
    vault kv put secret/live-ms-java olhovivo.token=$LIVE_MS_JAVA_OLHOVIVO_TOKEN &&
    vault kv put secret/my-new-ms db.password=$MY_NEW_MS_DB_PASSWORD api.key=$MY_NEW_MS_API_KEY
  "
```

**Step 3** — recreate the init container:

```bash
docker compose up -d --force-recreate vault-init
```

### Reading Secrets from a Microservice (Java example)

```java
// Using Spring Cloud Vault or the Vault SDK
// application.properties:
// spring.cloud.vault.uri=http://localhost:8200
// spring.cloud.vault.token=tcc-local-root-token
// spring.cloud.vault.kv.default-context=my-new-ms
```

### Logs

```bash
docker compose logs -f vault
docker compose logs -f vault-init
```

---

## Network

All containers share the `shared-infra-network` bridge network. Microservices can join it externally:

```yaml
# In your microservice's docker-compose.yml
networks:
  shared-infra-network:
    external: true
```

Then reference services by container name: `shared-redis`, `shared-influxdb`, `shared-vault`.

---

## Data Persistence

All data lives under `./data/` (gitignored):

```
data/
  redis/       # Redis AOF data
  influxdb/
    data/      # InfluxDB time-series data
    config/    # InfluxDB config
```

To wipe all data and start fresh:

```bash
docker compose down
rm -rf ./data
docker compose up -d
```
