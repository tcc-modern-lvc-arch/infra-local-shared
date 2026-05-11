# infra-local-shared

Shared local infrastructure for the TCC project — InfluxDB, MariaDB, HashiCorp Vault, the `event-hub` ingestion service, the `virtual-areas-ms-java` geofence service, and Grafana, all wired up via Docker Compose.

This repo is **infrastructure only**. The microservice code lives in sibling repos (`../event-hub`, `../virtual-areas-ms-java`, `../proto-shared`).

## Quick Start

```bash
cp .env.example .env
# fill in secret values in .env (only external API tokens — see "Environment Variables")
docker compose up -d
```

To recreate init containers after config changes:

```bash
docker compose up -d --force-recreate
```

To wipe all persisted data and start fresh:

```bash
docker compose down
rm -rf ./data
docker compose up -d
```

---

## Services

| Service | Container | Port | Purpose |
|---|---|---|---|
| InfluxDB | `shared-influxdb` | 8086 | Time-series store (CQRS write + read buckets) |
| MariaDB | `shared-mariadb` | 3306 | Relational store (CQRS write/read DBs + virtual_areas registry) |
| Vault | `shared-vault` | 8200 | Secret management (external API tokens only) |
| Grafana | `shared-grafana` | 3000 | Dashboards over the read-side stores |
| event-hub | `event-hub` | 50051 | gRPC event ingestion + outbox + projection workers |
| virtual-areas-ms-java | `virtual-areas-ms-java` | 8082 / 50052 | Geofence detector + Vaadin UI |

Init-only containers (run to completion, then exit): `shared-influxdb-init`, `shared-mariadb-init`, `shared-vault-init`, `proto-codegen`.

See `AGENTS.md` for the CQRS architecture diagram and the per-store schema.

---

## Environment Variables (`.env`)

Only **external API tokens** are kept in `.env` and seeded into Vault. All database credentials are hardcoded in `docker-compose.yml` (acceptable for a local thesis environment).

| File | Purpose | Committed |
|---|---|---|
| `.env.example` | Empty placeholders — source of truth | Yes |
| `.env` | Real secret values | No |

**Current variables:**

| Variable | Vault path | Key |
|---|---|---|
| `LIVE_MS_JAVA_OLHOVIVO_TOKEN` | `secret/live-ms-java` | `olhovivo.token` |
| `NVIDIA_NIM_API_KEY` | `secret/constructive-airsim-ms` | `nvidia.api_key` |

> When adding a new microservice, append its variables here and follow the steps in [Adding Secrets for a New Microservice](#adding-secrets-for-a-new-microservice).

---

## InfluxDB

- **URL:** http://localhost:8086
- **Org:** `tcc-org`
- **Admin token:** `tcc-local-super-secret-token`
- **Username:** `admin` / **Password:** `admin123`

Data persists under `./data/influxdb/`.

### Buckets

| Bucket | Retention | CQRS side | Purpose |
|---|---|---|---|
| `events` | infinite | Write | Raw checkin/checkout/move/photo/crash events written by event-hub |
| `projections` | 90 d | Read | Aggregated projections produced by projection workers |

### Web UI Walkthrough

1. Open http://localhost:8086
2. Log in with `admin` / `admin123`
3. **Data Explorer** (left sidebar) — pick bucket → measurement → fields → time range → **Submit**
4. **Load Data → Buckets → [bucket] → Add Data → Line Protocol** to write manually
5. **Load Data → API Tokens** to create scoped tokens per microservice

### Write Data (HTTP / line protocol)

```bash
curl -s -o /dev/null -w "%{http_code}" \
  -X POST "http://localhost:8086/api/v2/write?org=tcc-org&bucket=events&precision=s" \
  -H "Authorization: Token tcc-local-super-secret-token" \
  -H "Content-Type: text/plain" \
  --data-raw "cpu_usage,host=server01 value=42.5 $(date +%s)"
```

### Adding a New Bucket

Edit the `influxdb-init` entrypoint in `docker-compose.yml`, then:

```bash
docker compose up -d --force-recreate influxdb-init
```

### Logs

```bash
docker compose logs -f influxdb influxdb-init
```

---

## MariaDB

- **URL:** `localhost:3306`
- **Root password:** `tcc-root`

Data persists under `./data/mariadb/`.

### Databases

| Database | CQRS side | User | Password | Written by |
|---|---|---|---|---|
| `eventhub` | Write | `eventhub` | `tcc-eventhub` | event-hub (sqlx migrations) |
| `eventhub_read` | Read | `eventhub_read` | `tcc-eventhub-read` | projection workers (event-hub outbox) |
| `virtual_areas` | Registry | `virtual_areas` | `tcc-virtual-areas` | virtual-areas-ms-java (JPA) |

The `eventhub` user has **no access** to `eventhub_read` (CQRS boundary). The `eventhub_read` user has read-only `SELECT` on `virtual_areas.areas` so dashboards can JOIN human-readable area names.

Read-side schema lives in `mariadb/init/02_read_schema.sql`. Backfill from `event_log` into projection tables is handled by `mariadb/init/04_backfill_projections.sql` (idempotent — uses `INSERT IGNORE`).

### Connect

```bash
# Root (host)
mariadb -h localhost -u root -p

# Per-DB users (host)
mariadb -h localhost -u eventhub      -ptcc-eventhub      eventhub
mariadb -h localhost -u eventhub_read -ptcc-eventhub-read eventhub_read
mariadb -h localhost -u virtual_areas -ptcc-virtual-areas virtual_areas
```

### Logs

```bash
docker compose logs -f mariadb mariadb-init
```

---

## Grafana

- **URL:** http://localhost:3000
- **Login:** `admin` / `admin`

Provisioned datasources (auto-loaded from `grafana/provisioning/datasources/`):

| Datasource | Store |
|---|---|
| InfluxDB — Projections (Read) | `projections` bucket |
| InfluxDB — Events (Write) | `events` bucket |
| MariaDB — Projections (Read) | `eventhub_read` |
| MariaDB — Entity State (Write) | `eventhub` |
| MariaDB — Virtual Areas (Registry) | `virtual_areas` |

Provisioned dashboards live in `grafana/dashboards/`. Drop a `.json` file there and Grafana auto-loads it within 30 seconds.

The flagship dashboard is **LVC Read Side — CQRS Projections** (`/d/lvc-read-side`). It exposes `$lvc`, `$entity_type`, and `$area` template variables and renders the operational map plus alert/audit panels.

### Logs

```bash
docker compose logs -f grafana
```

---

## event-hub

- **gRPC port:** 50051
- **Build context:** `../event-hub`

Rust service that ingests gRPC events into the `events` InfluxDB bucket and the `eventhub` MariaDB DB, then drains the outbox into projection workers that populate the read-side stores. Started automatically once MariaDB and InfluxDB are healthy.

### Logs

```bash
docker compose logs -f event-hub
```

---

## virtual-areas-ms-java

- **HTTP / Vaadin UI:** http://localhost:8082
- **gRPC port:** 50052
- **Build context:** `../virtual-ms-java/virtual-areas`

Spring Boot + Vaadin service that owns the `virtual_areas` registry: defines polygons, circles, and corridors; tracks `entity_states` (which entities are currently inside which area); emits CHECKIN/CHECKOUT events to event-hub when the geofence triggers.

### Logs

```bash
docker compose logs -f virtual-areas-ms-java
```

---

## HashiCorp Vault

- **URL:** http://localhost:8200
- **Root token:** `tcc-local-root-token`

Vault runs in **dev mode** — all secrets are in-memory and reset on container restart. Acceptable for local development.

### Connect

```bash
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=tcc-local-root-token
```

### Read / Write Secrets

```bash
vault kv get secret/live-ms-java
vault kv get -field=olhovivo.token secret/live-ms-java
vault kv put secret/live-ms-java key1=value1 key2=value2
vault kv list secret/
```

### Adding Secrets for a New Microservice

By convention each microservice has its own path: `secret/<microservice-name>`.

**Step 1** — add the variable to `.env` and `.env.example`:

```env
# .env (real values — never commit)
MY_NEW_MS_API_KEY=abc123

# .env.example (empty placeholders — commit this)
MY_NEW_MS_API_KEY=
```

**Step 2** — reference it in the `vault-init` entrypoint in `docker-compose.yml`:

```yaml
entrypoint: >
  sh -c "
    vault kv put secret/live-ms-java        olhovivo.token=$LIVE_MS_JAVA_OLHOVIVO_TOKEN &&
    vault kv put secret/constructive-airsim-ms nvidia.api_key=$NVIDIA_NIM_API_KEY &&
    vault kv put secret/my-new-ms           api.key=$MY_NEW_MS_API_KEY
  "
```

**Step 3** — recreate the init container:

```bash
docker compose up -d --force-recreate vault-init
```

### Reading Secrets from a Microservice (Java)

```java
// application.properties
// spring.cloud.vault.uri=http://localhost:8200
// spring.cloud.vault.token=tcc-local-root-token
// spring.cloud.vault.kv.default-context=my-new-ms
```

### Logs

```bash
docker compose logs -f vault vault-init
```

---

## Network

All containers share the `shared-infra-network` bridge network. Microservices started outside this compose project can join it:

```yaml
# In your microservice's docker-compose.yml
networks:
  shared-infra-network:
    external: true
```

Then reference services by container name: `shared-influxdb`, `shared-mariadb`, `shared-vault`, `shared-grafana`, `event-hub`, `virtual-areas-ms-java`.

---

## Data Persistence

All persistent data lives under `./data/` (gitignored):

```
data/
  influxdb/
    data/      # InfluxDB time-series data
    config/    # InfluxDB config
  mariadb/     # MariaDB datadir (all three databases)
  grafana/     # Grafana SQLite + plugins + state
```

Vault is dev-mode (in-memory) and has no persistence. Restarting the container resets all secrets — `vault-init` re-seeds them from `.env` on next start.

To wipe everything:

```bash
docker compose down
rm -rf ./data
docker compose up -d
```
