-- Creates the virtual_areas write-side database and its user.
-- Run by mariadb-init after 01 and 02.
CREATE DATABASE IF NOT EXISTS virtual_areas CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'virtual_areas'@'%' IDENTIFIED BY 'tcc-virtual-areas';
GRANT ALL PRIVILEGES ON virtual_areas.* TO 'virtual_areas'@'%';

-- Read-only cross-DB grant: lets the eventhub_read datasource JOIN
-- virtual_areas.areas for human-readable names in Grafana panels.
-- virtual_areas is a registry, not a write boundary, so this does not
-- violate CQRS.
GRANT SELECT ON virtual_areas.* TO 'eventhub_read'@'%';

FLUSH PRIVILEGES;
