-- CQRS Read-side database.
-- Populated by projection workers that consume the outbox from eventhub (write side).
-- Grafana dashboards and reports query this database via the eventhub_read user.
--
-- This script runs automatically on first MariaDB startup because it is mounted
-- in /docker-entrypoint-initdb.d/.  The write-side database (eventhub) is
-- already created by the MARIADB_DATABASE env var in docker-compose.yml.

CREATE DATABASE IF NOT EXISTS eventhub_read
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

-- Dedicated user for the read side.
-- Used by projection workers (write projections) and Grafana (read projections).
CREATE USER IF NOT EXISTS 'eventhub_read'@'%' IDENTIFIED BY 'tcc-eventhub-read';
GRANT ALL PRIVILEGES ON eventhub_read.* TO 'eventhub_read'@'%';

-- The write-side user (eventhub) must NOT have access to eventhub_read so the
-- CQRS boundary is enforced at the DB level.
REVOKE ALL PRIVILEGES, GRANT OPTION FROM 'eventhub'@'%';
GRANT ALL PRIVILEGES ON eventhub.* TO 'eventhub'@'%';

FLUSH PRIVILEGES;
