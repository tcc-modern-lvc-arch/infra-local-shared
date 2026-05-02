-- CQRS read-side schema for eventhub_read.
-- Populated by the outbox worker via the 'mariadb_read' target.
-- Grafana panels and reports query these tables through the eventhub_read datasource.

USE eventhub_read;

-- ── area_stats ────────────────────────────────────────────────────────────────
-- Aggregated counters per (area, entity_type, lvc).
-- Updated on every check-in / check-out via UPSERT in the projection worker.
CREATE TABLE IF NOT EXISTS area_stats (
    area_id         VARCHAR(36)  NOT NULL,
    entity_type     VARCHAR(50)  NOT NULL,
    lvc             VARCHAR(20)  NOT NULL DEFAULT 'LIVE',
    total_checkins  BIGINT       NOT NULL DEFAULT 0,
    total_checkouts BIGINT       NOT NULL DEFAULT 0,
    active_count    INT          NOT NULL DEFAULT 0,
    last_event_at   DATETIME,
    last_updated    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
                                          ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (area_id, entity_type, lvc)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ── event_log ─────────────────────────────────────────────────────────────────
-- Append-only denormalised log of every accepted event.
-- UNIQUE on event_id ensures idempotency: outbox retries are silently ignored
-- (INSERT IGNORE) so the log is never duplicated.
CREATE TABLE IF NOT EXISTS event_log (
    id           BIGINT       NOT NULL AUTO_INCREMENT,
    event_id     VARCHAR(36)  NOT NULL,
    area_id      VARCHAR(36)  NOT NULL,
    entity_id    VARCHAR(255) NOT NULL,
    entity_type  VARCHAR(50)  NOT NULL,
    event_type   VARCHAR(20)  NOT NULL,
    lvc          VARCHAR(20)  NOT NULL,
    source       VARCHAR(100),
    lat          DECIMAL(10, 8),
    lon          DECIMAL(11, 8),
    occurred_at  DATETIME     NOT NULL,
    recorded_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE  KEY uk_event_log_event_id (event_id),
    INDEX        idx_event_log_area   (area_id,    occurred_at),
    INDEX        idx_event_log_entity (entity_id,  occurred_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
