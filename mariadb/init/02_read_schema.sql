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

-- ── flood_alerts ──────────────────────────────────────────────────────────────
-- Flood alerts reported by CGESP per area.
-- Populated by the projection worker consuming CGESP alert events.
CREATE TABLE IF NOT EXISTS flood_alerts (
    id           BIGINT       NOT NULL AUTO_INCREMENT,
    event_id     VARCHAR(36)  NOT NULL,
    area_id      VARCHAR(36)  NOT NULL,
    alert_type   VARCHAR(50)  NOT NULL,
    severity     ENUM('INFO','WARNING','CRITICAL') NOT NULL DEFAULT 'INFO',
    message      TEXT,
    lat          DECIMAL(10, 8),
    lon          DECIMAL(11, 8),
    occurred_at  DATETIME     NOT NULL,
    recorded_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE  KEY uk_flood_alerts_event_id (event_id),
    INDEX        idx_flood_alerts_area (area_id, occurred_at),
    INDEX        idx_flood_alerts_sev  (severity, occurred_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ── drone_photos ──────────────────────────────────────────────────────────────
-- Metadata and base64-encoded images captured by AirSim drones.
-- Populated by the projection worker consuming BusPhotoEvent.
CREATE TABLE IF NOT EXISTS drone_photos (
    id           BIGINT       NOT NULL AUTO_INCREMENT,
    event_id     VARCHAR(36)  NOT NULL,
    drone_id     VARCHAR(255) NOT NULL,
    mission_id   VARCHAR(255),
    area_id      VARCHAR(36),
    image_base64 LONGTEXT,
    lat          DECIMAL(10, 8),
    lon          DECIMAL(11, 8),
    altitude     DECIMAL(10, 2),
    captured_at  DATETIME     NOT NULL,
    recorded_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE  KEY uk_drone_photos_event_id (event_id),
    INDEX        idx_drone_photos_drone   (drone_id, captured_at),
    INDEX        idx_drone_photos_mission (mission_id, captured_at),
    INDEX        idx_drone_photos_area    (area_id, captured_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ── drone_crashes ─────────────────────────────────────────────────────────────
-- CRASH events from AirSim drones (collision with obstacles).
-- Populated by the projection worker consuming EventKind::Crash.
CREATE TABLE IF NOT EXISTS drone_crashes (
    id               BIGINT       NOT NULL AUTO_INCREMENT,
    event_id         VARCHAR(36)  NOT NULL,
    drone_id         VARCHAR(255) NOT NULL,
    area_id          VARCHAR(36),
    severity         DECIMAL(3, 2),
    collision_object VARCHAR(255),
    lat              DECIMAL(10, 8),
    lon              DECIMAL(11, 8),
    altitude         DECIMAL(10, 2),
    occurred_at      DATETIME     NOT NULL,
    recorded_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE  KEY uk_drone_crashes_event_id (event_id),
    INDEX        idx_drone_crashes_drone  (drone_id, occurred_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
