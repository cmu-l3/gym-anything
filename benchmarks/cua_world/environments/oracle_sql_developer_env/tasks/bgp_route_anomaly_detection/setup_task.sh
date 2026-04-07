#!/bin/bash
# Setup script for BGP Route Anomaly Detection task
echo "=== Setting up BGP Route Anomaly Detection ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /home/ga/.task_start_time

# ---------------------------------------------------------------
# 1. Verify Oracle is running
# ---------------------------------------------------------------
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi
echo "Oracle container is running"

# ---------------------------------------------------------------
# 2. Clean up previous run artifacts
# ---------------------------------------------------------------
echo "Cleaning up previous run artifacts..."

oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER net_admin CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true
sleep 2

# ---------------------------------------------------------------
# 3. Create NET_ADMIN schema
# ---------------------------------------------------------------
echo "Creating NET_ADMIN schema..."

oracle_query "CREATE USER net_admin IDENTIFIED BY NetAdmin2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO net_admin;
GRANT RESOURCE TO net_admin;
GRANT CREATE VIEW TO net_admin;
GRANT CREATE MATERIALIZED VIEW TO net_admin;
GRANT CREATE PROCEDURE TO net_admin;
GRANT CREATE JOB TO net_admin;
GRANT CREATE SESSION TO net_admin;
GRANT CREATE TABLE TO net_admin;
EXIT;" "system"

echo "NET_ADMIN user created"

# ---------------------------------------------------------------
# 4. Create tables and populate data
# ---------------------------------------------------------------
echo "Creating tables..."

sudo docker exec -i oracle-xe sqlplus -s net_admin/NetAdmin2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE TABLE bgp_routes (
    route_id       NUMBER PRIMARY KEY,
    prefix_base    VARCHAR2(15) NOT NULL,
    prefix_length  NUMBER NOT NULL,
    origin_asn     NUMBER NOT NULL,
    as_path        VARCHAR2(100),
    date_seen      DATE DEFAULT SYSDATE
);

CREATE TABLE bogon_space (
    bogon_id       NUMBER PRIMARY KEY,
    prefix_base    VARCHAR2(15) NOT NULL,
    prefix_length  NUMBER NOT NULL,
    description    VARCHAR2(100)
);

-- Insert Bogon Space (RFC 1918, RFC 6598, etc.)
INSERT INTO bogon_space VALUES (1, '10.0.0.0', 8, 'RFC 1918 Private Network');
INSERT INTO bogon_space VALUES (2, '172.16.0.0', 12, 'RFC 1918 Private Network');
INSERT INTO bogon_space VALUES (3, '192.168.0.0', 16, 'RFC 1918 Private Network');
INSERT INTO bogon_space VALUES (4, '100.64.0.0', 10, 'RFC 6598 Carrier Grade NAT');
INSERT INTO bogon_space VALUES (5, '127.0.0.0', 8, 'Loopback');
INSERT INTO bogon_space VALUES (6, '224.0.0.0', 4, 'Multicast');

-- Insert BGP Routes
-- 1. Normal routes
INSERT INTO bgp_routes VALUES (101, '8.8.8.0', 24, 15169, '3356 2914 15169', SYSDATE);
INSERT INTO bgp_routes VALUES (102, '1.1.1.0', 24, 13335, '1299 13335', SYSDATE);
INSERT INTO bgp_routes VALUES (103, '1.0.0.0', 24, 13335, '1299 13335', SYSDATE);
INSERT INTO bgp_routes VALUES (104, '204.14.232.0', 21, 1239, '1239', SYSDATE);
INSERT INTO bgp_routes VALUES (105, '12.0.0.0', 8, 7018, '7018', SYSDATE);

-- 2. Bogon Leaks (should be detected)
INSERT INTO bgp_routes VALUES (201, '10.55.0.0', 16, 65000, '3356 65000', SYSDATE); -- Inside 10/8
INSERT INTO bgp_routes VALUES (202, '192.168.100.0', 24, 65001, '1299 65001', SYSDATE); -- Inside 192.168/16
INSERT INTO bgp_routes VALUES (203, '100.70.0.0', 16, 65002, '2914 65002', SYSDATE); -- Inside 100.64/10

-- 3. Route Hijacks (more specific route overriding legitimate route by different ASN)
-- Victim: 203.0.113.0/24 (ASN 100)
INSERT INTO bgp_routes VALUES (301, '203.0.113.0', 24, 100, '3356 100', SYSDATE);
-- Hijacker: 203.0.113.128/25 (ASN 666) -> Fits inside the /24
INSERT INTO bgp_routes VALUES (302, '203.0.113.128', 25, 666, '1299 666', SYSDATE);

-- Victim: 198.51.100.0/22 (ASN 200)
INSERT INTO bgp_routes VALUES (303, '198.51.100.0', 22, 200, '7018 200', SYSDATE);
-- Hijacker: 198.51.101.0/24 (ASN 777)
INSERT INTO bgp_routes VALUES (304, '198.51.101.0', 24, 777, '3356 777', SYSDATE);

-- 4. Overlapping Subnets (SAME ASN - tests footprint deduplication)
-- ASN 15169 advertises a /16 and a /24 inside it. Footprint should only be 65536, NOT 65536+256.
INSERT INTO bgp_routes VALUES (401, '8.8.0.0', 16, 15169, '15169', SYSDATE);

-- ASN 3356 advertises a /12, and multiple /16s inside it. 
INSERT INTO bgp_routes VALUES (402, '4.0.0.0', 12, 3356, '3356', SYSDATE); -- capacity: 1,048,576
INSERT INTO bgp_routes VALUES (403, '4.2.0.0', 16, 3356, '3356', SYSDATE);
INSERT INTO bgp_routes VALUES (404, '4.3.0.0', 16, 3356, '3356', SYSDATE);
-- And a separate non-overlapping route for ASN 3356
INSERT INTO bgp_routes VALUES (405, '65.0.0.0', 16, 3356, '3356', SYSDATE); -- capacity: 65,536
-- Total for 3356 should be 1,048,576 + 65,536 = 1,114,112

COMMIT;
EXIT;
EOSQL

# Add many synthetic normal routes to make it feel like a real table
echo "Generating additional background routing data..."
sudo docker exec -i oracle-xe sqlplus -s net_admin/NetAdmin2024@//localhost:1521/XEPDB1 << 'EOSQL'
BEGIN
  FOR i IN 1..500 LOOP
    INSERT INTO bgp_routes (route_id, prefix_base, prefix_length, origin_asn, date_seen)
    VALUES (
      1000 + i,
      TRUNC(DBMS_RANDOM.VALUE(11, 99)) || '.' || TRUNC(DBMS_RANDOM.VALUE(0, 255)) || '.' || TRUNC(DBMS_RANDOM.VALUE(0, 255)) || '.0',
      TRUNC(DBMS_RANDOM.VALUE(16, 24)),
      TRUNC(DBMS_RANDOM.VALUE(1000, 64000)),
      SYSDATE - DBMS_RANDOM.VALUE(0, 30)
    );
  END LOOP;
  COMMIT;
END;
/
EXIT;
EOSQL

echo "Data populated successfully."

# Ensure export directory exists
mkdir -p /home/ga/Documents/exports
chown -R ga:ga /home/ga/Documents/exports

# Start GUI if requested or just let post_start handle it.
echo "=== Task Setup Complete ==="