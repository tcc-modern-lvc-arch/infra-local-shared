# AGENTS.md

This file provides guidance to AI coding agents working in this repository.

## Purpose

This repo defines shared local infrastructure for the TCC project using Docker Compose. It is not a software application — it has no build system, tests, or linter. All operations are Docker commands.

## Common Commands

```bash
# Start all services (detached)
docker compose up -d

# Start with fresh init containers (useful after config changes)
docker compose up -d --force-recreate

# Stop all services
docker compose down

# View logs for a specific service
docker compose logs -f <service>

# Restart a single service
docker compose restart <service>
```

## CQRS Store Architecture

```
                 ┌─── WRITE SIDE ────────────────────────┐
                 │  InfluxDB  bucket  : events            │
                 │  MariaDB   database: eventhub          │
                 └───────────────────────────────────────┘
                             │ outbox + projection workers
                             ▼
                 ┌─── READ SIDE ─────────────────────────┐
                 │  InfluxDB  bucket  : projections       │
                 │  MariaDB   database: eventhub_read     │
                 └───────────────────────────────────────┘
                             │
                             ▼ Grafana dashboards / reports
```

## Services

| Container | Port | Role |
|---|---|---|
| `shared-influxdb` | 8086 | Time-series store (both CQRS sides) |
| `shared-influxdb-init` | — | Creates `projections` bucket on first start |
| `shared-mariadb` | 3306 | Relational store (both CQRS sides + virtual_areas registry) |
| `shared-mariadb-init` | — | Creates `eventhub_read`/`virtual_areas` DBs + schema on first start, then backfills projections |
| `event-hub` | 50051 | gRPC event ingestion — built from `../event-hub` |
| `shared-vault` | 8200 | Vault dev mode — external API tokens only |
| `shared-vault-init` | — | Seeds `.env` tokens into Vault KV |
| `shared-grafana` | 3000 | Dashboards — reads from read-side stores |

## InfluxDB

| Bucket | Retention | CQRS side | Written by |
|---|---|---|---|
| `events` | ∞ | Write | event-hub (outbox worker) |
| `projections` | 90 d | Read | projection workers (event-hub outbox) |

- Org: `tcc-org`
- Admin token: `tcc-local-super-secret-token`
- Admin user: `admin` / `admin123`

To add a bucket: append an `influx bucket create` to the `influxdb-init` entrypoint, then `docker compose up -d --force-recreate influxdb-init`.

## MariaDB

| Database | CQRS side | User | Password | Written by |
|---|---|---|---|---|
| `eventhub` | Write | `eventhub` | `tcc-eventhub` | event-hub |
| `eventhub_read` | Read | `eventhub_read` | `tcc-eventhub-read` | projection workers (event-hub outbox) |
| `virtual_areas` | Registry | `virtual_areas` | `tcc-virtual-areas` | virtual-areas-ms-java (JPA) |

- Root password: `tcc-root`
- The `eventhub` user has **no access** to `eventhub_read` (boundary enforced by `mariadb/init/01_read_database.sql`).
- `eventhub_read` has `SELECT` on `virtual_areas.areas` (granted by `03_virtual_areas_database.sql`) so dashboard panels can `LEFT JOIN` for human-readable area names.

Schema for `eventhub` is managed by sqlx migrations in the event-hub repo.  
Schema for `eventhub_read` is defined in `mariadb/init/02_read_schema.sql` and populated by projection workers in the event-hub.

### Read-side tables

| Table | Populated by | Description |
|---|---|---|
| `area_stats` | Projection worker (CHECKIN/CHECKOUT) | Aggregated counters per area/entity_type/lvc |
| `event_log` | Projection worker (all events) | Append-only denormalised event log |
| `flood_alerts` | Projection worker (FloodArea MOVE) | CGESP flood alerts per area |
| `drone_photos` | Projection worker (PHOTO) | AirSim drone photo metadata + base64 images |
| `drone_crashes` | Projection worker (CRASH) | AirSim drone collision events |

To re-apply the read-side schema after changes: `docker compose up -d --force-recreate mariadb-init`.

## Grafana Datasources (auto-provisioned)

| Name | Type | Store | Default |
|---|---|---|---|
| InfluxDB — Projections (Read) | InfluxDB / Flux | `projections` bucket | ✓ |
| InfluxDB — Events (Write) | InfluxDB / Flux | `events` bucket | — |
| MariaDB — Projections (Read) | MySQL | `eventhub_read` | — |
| MariaDB — Entity State (Write) | MySQL | `eventhub` | — |
| MariaDB — Virtual Areas (Registry) | MySQL | `virtual_areas` | — |

## Secrets Policy

Only **external API tokens** are treated as secrets and kept in `.env` (gitignored):
- `LIVE_MS_JAVA_OLHOVIVO_TOKEN`
- `NVIDIA_NIM_API_KEY`

All database credentials are hardcoded in `docker-compose.yml` — acceptable for a local thesis environment.

## Adding New Buckets, Tables, or Secrets

- **InfluxDB buckets**: add `influx bucket create` to `influxdb-init` entrypoint, then `--force-recreate influxdb-init`.
- **MariaDB read-side tables**: add `CREATE TABLE IF NOT EXISTS` to `mariadb/init/02_read_schema.sql`, then `--force-recreate mariadb-init`.
- **Grafana dashboards**: add `.json` files to `grafana/dashboards/` — auto-provisioned on next Grafana start.
- **Vault secrets**: add `vault kv put` to `vault-init` entrypoint, then `--force-recreate vault-init`.
