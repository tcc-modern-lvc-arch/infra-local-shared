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
| `shared-mariadb` | 3306 | Relational store (both CQRS sides) |
| `shared-mariadb-init` | — | Creates `eventhub_read` DB + schema on first start |
| `event-hub` | 50051 | gRPC event ingestion — built from `../event-hub` |
| `shared-vault` | 8200 | Vault dev mode — external API tokens only |
| `shared-vault-init` | — | Seeds `.env` tokens into Vault KV |
| `shared-grafana` | 3000 | Dashboards — reads from read-side stores |

## InfluxDB

| Bucket | Retention | CQRS side | Written by |
|---|---|---|---|
| `events` | ∞ | Write | event-hub (outbox worker) |
| `projections` | 90 d | Read | projection workers (future) |

- Org: `tcc-org`
- Admin token: `tcc-local-super-secret-token`
- Admin user: `admin` / `admin123`

To add a bucket: append an `influx bucket create` to the `influxdb-init` entrypoint, then `docker compose up -d --force-recreate influxdb-init`.

## MariaDB

| Database | CQRS side | User | Password | Written by |
|---|---|---|---|---|
| `eventhub` | Write | `eventhub` | `tcc-eventhub` | event-hub |
| `eventhub_read` | Read | `eventhub_read` | `tcc-eventhub-read` | projection workers (future) |

- Root password: `tcc-root`
- The `eventhub` user has **no access** to `eventhub_read` (boundary enforced by `mariadb/init/01_read_database.sql`).

Schema for `eventhub` is managed by sqlx migrations in the event-hub repo.  
Schema for `eventhub_read` will be managed by the projection worker (TBD).

## Grafana Datasources (auto-provisioned)

| Name | Type | Store | Default |
|---|---|---|---|
| InfluxDB — Projections (Read) | InfluxDB / Flux | `projections` bucket | ✓ |
| InfluxDB — Events (Write) | InfluxDB / Flux | `events` bucket | — |
| MariaDB — Projections (Read) | MySQL | `eventhub_read` | — |
| MariaDB — Entity State (Write) | MySQL | `eventhub` | — |

## Secrets Policy

Only **external API tokens** are treated as secrets and kept in `.env` (gitignored):
- `LIVE_MS_JAVA_OLHOVIVO_TOKEN`
- `NVIDIA_NIM_API_KEY`

All database credentials are hardcoded in `docker-compose.yml` — acceptable for a local thesis environment.

## Adding New Buckets or Secrets

- **InfluxDB buckets**: add `influx bucket create` to `influxdb-init` entrypoint, then `--force-recreate influxdb-init`.
- **Vault secrets**: add `vault kv put` to `vault-init` entrypoint, then `--force-recreate vault-init`.
