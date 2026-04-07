#!/bin/bash
# Setup script for Streaming Royalty Apportionment task
echo "=== Setting up Streaming Royalty Apportionment Task ==="

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
  EXECUTE IMMEDIATE 'DROP USER royalty_admin CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true
sleep 2

# ---------------------------------------------------------------
# 3. Create ROYALTY schema with royalty_admin user
# ---------------------------------------------------------------
echo "Creating ROYALTY_ADMIN schema..."
oracle_query "CREATE USER royalty_admin IDENTIFIED BY Royalty2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO royalty_admin;
GRANT RESOURCE TO royalty_admin;
GRANT CREATE VIEW TO royalty_admin;
GRANT CREATE MATERIALIZED VIEW TO royalty_admin;
GRANT CREATE SESSION TO royalty_admin;
GRANT CREATE TABLE TO royalty_admin;
EXIT;" "system"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create royalty_admin user"
    exit 1
fi

# ---------------------------------------------------------------
# 4. Create tables and insert deterministic test data
# ---------------------------------------------------------------
echo "Creating tables and loading data..."

sudo docker exec -i oracle-xe sqlplus -s royalty_admin/Royalty2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE TABLE tracks (
    track_id      VARCHAR2(30) PRIMARY KEY,
    isrc          VARCHAR2(15),
    title         VARCHAR2(200),
    artist_name   VARCHAR2(200),
    duration_sec  NUMBER
);

CREATE TABLE rights_holders (
    holder_id     NUMBER PRIMARY KEY,
    holder_name   VARCHAR2(100),
    entity_type   VARCHAR2(20),
    tax_country   VARCHAR2(2)
);

CREATE TABLE splits (
    split_id      NUMBER PRIMARY KEY,
    track_id      VARCHAR2(30) REFERENCES tracks(track_id),
    holder_id     NUMBER REFERENCES rights_holders(holder_id),
    role          VARCHAR2(20),
    ownership_pct NUMBER(5,2)
);

CREATE TABLE streams (
    stream_id       NUMBER PRIMARY KEY,
    track_id        VARCHAR2(30) REFERENCES tracks(track_id),
    stream_timestamp TIMESTAMP,
    user_tier       VARCHAR2(10),
    country_code    VARCHAR2(2)
);

-- Insert Tracks
INSERT INTO tracks VALUES ('T1', 'US1234567890', 'Hit Song', 'Pop Star', 210);
INSERT INTO tracks VALUES ('T2', 'US1234567891', 'Bad Split', 'Math Rockers', 180);
INSERT INTO tracks VALUES ('T3', 'US1234567892', 'Indie Anthem', 'Solo Artist', 245);
INSERT INTO tracks VALUES ('T4', 'US1234567893', 'Over 100', 'Greedy Duo', 195);
INSERT INTO tracks VALUES ('T5', 'US1234567894', 'Mega Collab', 'Various', 300);

-- Insert Rights Holders
INSERT INTO rights_holders VALUES (1, 'Alice Publishing', 'PUBLISHER', 'US');
INSERT INTO rights_holders VALUES (2, 'Bob Records', 'LABEL', 'UK');
INSERT INTO rights_holders VALUES (3, 'Charlie Tunes', 'PUBLISHER', 'CA');
INSERT INTO rights_holders VALUES (4, 'Dave Productions', 'LABEL', 'US');
INSERT INTO rights_holders VALUES (5, 'Eve Music', 'PUBLISHER', 'AU');

-- Insert Splits (Seeding the data isolation logic)
-- T1: Valid (50 + 50 = 100)
INSERT INTO splits VALUES (1, 'T1', 1, 'COMPOSER', 50.00);
INSERT INTO splits VALUES (2, 'T1', 2, 'MASTER', 50.00);

-- T2: Invalid (33.33 + 33.33 + 33.33 = 99.99) - Goes to Suspense
INSERT INTO splits VALUES (3, 'T2', 3, 'COMPOSER', 33.33);
INSERT INTO splits VALUES (4, 'T2', 4, 'MASTER', 33.33);
INSERT INTO splits VALUES (5, 'T2', 5, 'LYRICIST', 33.33);

-- T3: Valid (100)
INSERT INTO splits VALUES (6, 'T3', 1, 'MASTER', 100.00);

-- T4: Invalid (60 + 50 = 110) - Goes to Suspense
INSERT INTO splits VALUES (7, 'T4', 2, 'MASTER', 60.00);
INSERT INTO splits VALUES (8, 'T4', 3, 'COMPOSER', 50.00);

-- T5: Valid (25 * 4 = 100)
INSERT INTO splits VALUES (9, 'T5', 1, 'COMPOSER', 25.00);
INSERT INTO splits VALUES (10, 'T5', 2, 'MASTER', 25.00);
INSERT INTO splits VALUES (11, 'T5', 3, 'LYRICIST', 25.00);
INSERT INTO splits VALUES (12, 'T5', 4, 'PRODUCER', 25.00);

-- Insert Streams using PL/SQL block for volume
DECLARE
    v_stream_id NUMBER := 1;
    PROCEDURE add_streams(p_track VARCHAR2, p_premium NUMBER, p_free NUMBER) IS
    BEGIN
        FOR i IN 1..p_premium LOOP
            INSERT INTO streams VALUES (v_stream_id, p_track, SYSDATE - DBMS_RANDOM.VALUE(0, 90), 'PREMIUM', 'US');
            v_stream_id := v_stream_id + 1;
        END LOOP;
        FOR i IN 1..p_free LOOP
            INSERT INTO streams VALUES (v_stream_id, p_track, SYSDATE - DBMS_RANDOM.VALUE(0, 90), 'FREE', 'US');
            v_stream_id := v_stream_id + 1;
        END LOOP;
    END;
BEGIN
    -- T1: 1000 P ($7.50), 2000 F ($3.00) = $10.50 Total
    add_streams('T1', 1000, 2000);
    
    -- T2: 5000 P ($37.50), 0 F ($0.00) = $37.50 Total (Suspense)
    add_streams('T2', 5000, 0);
    
    -- T3: 0 P ($0.00), 10000 F ($15.00) = $15.00 Total
    add_streams('T3', 0, 10000);
    
    -- T4: 200 P ($1.50), 500 F ($0.75) = $2.25 Total (Suspense)
    add_streams('T4', 200, 500);
    
    -- T5: 20000 P ($150.00), 50000 F ($75.00) = $225.00 Total
    add_streams('T5', 20000, 50000);
    
    COMMIT;
END;
/
EXIT;
EOSQL

echo "Data populated successfully."

# ---------------------------------------------------------------
# 5. Pre-configure SQL Developer connection
# ---------------------------------------------------------------
ensure_hr_connection "Royalty Database" "royalty_admin" "Royalty2024"

# ---------------------------------------------------------------
# 6. Open SQL Developer and focus window
# ---------------------------------------------------------------
open_hr_connection_in_sqldeveloper 2>/dev/null || true

# Maximize SQL Developer specifically
WID=$(DISPLAY=:1 wmctrl -l | grep -iE "sql developer|oracle sql" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Initial screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Task setup complete ==="