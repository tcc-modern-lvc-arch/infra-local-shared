-- Backfill projections from historic event_log rows.
-- Re-runnable: every INSERT uses INSERT IGNORE against UNIQUE(event_id), so
-- rows already projected by the worker (or by a previous backfill run) are skipped.

USE eventhub_read;

-- ── flood_alerts backfill ─────────────────────────────────────────────────────
-- Replays MOVE events for flood_area entities. severity defaults to 'INFO'
-- because the original CGESP severity string lives in the JSON payload, not in
-- event_log columns.
INSERT IGNORE INTO flood_alerts
    (event_id, area_id, alert_type, severity, message, lat, lon, occurred_at)
SELECT
    event_id,
    area_id,
    'flood',
    'INFO',
    CONCAT('Backfilled flood alert — original event_type=', event_type),
    lat,
    lon,
    occurred_at
FROM event_log
WHERE entity_type = 'flood_area'
  AND event_type  = 'MOVE';

-- ── drone_photos backfill ─────────────────────────────────────────────────────
-- image_base64 and mission_id stay NULL: JPEG bytes were stripped during
-- proto_to_domain and never persisted in event_log; mission_id likewise was not
-- denormalised into event_log.
INSERT IGNORE INTO drone_photos
    (event_id, drone_id, mission_id, area_id, image_base64,
     lat, lon, altitude, captured_at)
SELECT
    event_id,
    entity_id,
    NULL,
    area_id,
    NULL,
    lat,
    lon,
    NULL,
    occurred_at
FROM event_log
WHERE event_type = 'PHOTO';

-- ── drone_crashes backfill ────────────────────────────────────────────────────
-- severity / collision_object stay NULL — same reason as drone_photos above:
-- the raw DronePayload fields were not denormalised into event_log.
INSERT IGNORE INTO drone_crashes
    (event_id, drone_id, area_id, severity, collision_object,
     lat, lon, altitude, occurred_at)
SELECT
    event_id,
    entity_id,
    area_id,
    NULL,
    NULL,
    lat,
    lon,
    NULL,
    occurred_at
FROM event_log
WHERE event_type = 'CRASH';
