#!/bin/bash
echo "=== Setting up Baseball Statcast Pattern Recognition Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /home/ga/.task_start_time

# Verify Oracle container is running
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi
echo "Oracle container is running"

# Drop and recreate the BASEBALL_OPS user cleanly
echo "Setting up BASEBALL_OPS schema..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER baseball_ops CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true

sleep 2

oracle_query "CREATE USER baseball_ops IDENTIFIED BY Statcast2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO baseball_ops;
GRANT RESOURCE TO baseball_ops;
GRANT CREATE VIEW TO baseball_ops;
GRANT CREATE SESSION TO baseball_ops;
GRANT CREATE TABLE TO baseball_ops;
EXIT;" "system"

echo "BASEBALL_OPS user created with required privileges"

# Create STATCAST_PITCHES table
echo "Creating STATCAST_PITCHES table..."
oracle_query "CREATE TABLE statcast_pitches (
  pitch_id        NUMBER PRIMARY KEY,
  game_pk         NUMBER,
  game_date       DATE,
  at_bat_number   NUMBER,
  pitch_number    NUMBER, 
  pitcher_id      NUMBER,
  pitcher_name    VARCHAR2(100),
  batter_id       NUMBER,
  batter_name     VARCHAR2(100),
  inning          NUMBER,
  pitch_type      VARCHAR2(2),
  release_speed   NUMBER(5,2),
  zone            NUMBER,
  description     VARCHAR2(50), 
  events          VARCHAR2(50), 
  stand           VARCHAR2(1), 
  p_throws        VARCHAR2(1),
  balls           NUMBER,
  strikes         NUMBER
);
EXIT;" "baseball_ops" "Statcast2024"

# Insert sample pitch data
echo "Inserting sample pitch data..."
sudo docker exec -i oracle-xe sqlplus -s baseball_ops/Statcast2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK OFF

INSERT INTO statcast_pitches VALUES (1, 1001, DATE '2024-04-01', 1, 1, 453286, 'Cole, Gerrit', 646240, 'Devers, Rafael', 1, 'FF', 99.0, 5, 'called_strike', NULL, 'L', 'R', 0, 0);
INSERT INTO statcast_pitches VALUES (2, 1001, DATE '2024-04-01', 1, 2, 453286, 'Cole, Gerrit', 646240, 'Devers, Rafael', 1, 'SL', 89.0, 14, 'foul_tip', NULL, 'L', 'R', 0, 1);
INSERT INTO statcast_pitches VALUES (3, 1001, DATE '2024-04-01', 1, 3, 453286, 'Cole, Gerrit', 646240, 'Devers, Rafael', 1, 'FF', 99.5, 3, 'swinging_strike', 'strikeout', 'L', 'R', 0, 2);

INSERT INTO statcast_pitches VALUES (4, 1001, DATE '2024-04-01', 2, 1, 453286, 'Cole, Gerrit', 592450, 'Judge, Aaron', 1, 'FF', 98.0, 12, 'ball', NULL, 'R', 'R', 0, 0);
INSERT INTO statcast_pitches VALUES (5, 1001, DATE '2024-04-01', 2, 2, 453286, 'Cole, Gerrit', 592450, 'Judge, Aaron', 1, 'FF', 98.5, 5, 'called_strike', NULL, 'R', 'R', 1, 0);
INSERT INTO statcast_pitches VALUES (6, 1001, DATE '2024-04-01', 2, 3, 453286, 'Cole, Gerrit', 592450, 'Judge, Aaron', 1, 'SL', 88.5, 14, 'swinging_strike', NULL, 'R', 'R', 1, 1);
INSERT INTO statcast_pitches VALUES (7, 1001, DATE '2024-04-01', 2, 4, 453286, 'Cole, Gerrit', 592450, 'Judge, Aaron', 1, 'FF', 99.0, 3, 'swinging_strike', 'strikeout', 'R', 'R', 1, 2);

INSERT INTO statcast_pitches VALUES (8, 1001, DATE '2024-04-01', 3, 1, 453286, 'Cole, Gerrit', 123456, 'Batter 3', 1, 'FF', 98.5, 5, 'ball', NULL, 'R', 'R', 0, 0);
INSERT INTO statcast_pitches VALUES (9, 1001, DATE '2024-04-01', 3, 2, 453286, 'Cole, Gerrit', 123456, 'Batter 3', 1, 'FF', 99.0, 5, 'ball', NULL, 'R', 'R', 1, 0);
INSERT INTO statcast_pitches VALUES (10, 1001, DATE '2024-04-01', 3, 3, 453286, 'Cole, Gerrit', 123456, 'Batter 3', 1, 'FF', 98.0, 5, 'called_strike', NULL, 'R', 'R', 2, 0);
INSERT INTO statcast_pitches VALUES (11, 1001, DATE '2024-04-01', 3, 4, 453286, 'Cole, Gerrit', 123456, 'Batter 3', 1, 'FF', 98.5, 5, 'foul', NULL, 'R', 'R', 2, 1);
INSERT INTO statcast_pitches VALUES (12, 1001, DATE '2024-04-01', 3, 5, 453286, 'Cole, Gerrit', 123456, 'Batter 3', 1, 'FF', 99.5, 5, 'in_play', 'groundout', 'R', 'R', 2, 2);

INSERT INTO statcast_pitches VALUES (13, 1001, DATE '2024-04-01', 25, 1, 453286, 'Cole, Gerrit', 646240, 'Devers, Rafael', 7, 'FF', 95.0, 5, 'ball', NULL, 'L', 'R', 0, 0);
INSERT INTO statcast_pitches VALUES (14, 1001, DATE '2024-04-01', 25, 2, 453286, 'Cole, Gerrit', 646240, 'Devers, Rafael', 7, 'FF', 94.5, 5, 'ball', NULL, 'L', 'R', 1, 0);
INSERT INTO statcast_pitches VALUES (15, 1001, DATE '2024-04-01', 25, 3, 453286, 'Cole, Gerrit', 646240, 'Devers, Rafael', 7, 'FF', 94.0, 5, 'called_strike', NULL, 'L', 'R', 2, 0);
INSERT INTO statcast_pitches VALUES (16, 1001, DATE '2024-04-01', 25, 4, 453286, 'Cole, Gerrit', 646240, 'Devers, Rafael', 7, 'FF', 94.0, 5, 'foul', NULL, 'L', 'R', 2, 1);
INSERT INTO statcast_pitches VALUES (17, 1001, DATE '2024-04-01', 25, 5, 453286, 'Cole, Gerrit', 646240, 'Devers, Rafael', 7, 'FF', 93.5, 5, 'in_play', 'home_run', 'L', 'R', 2, 2);

INSERT INTO statcast_pitches VALUES (18, 1002, DATE '2024-04-02', 1, 1, 434378, 'Verlander, Justin', 111111, 'Batter 4', 1, 'FF', 94.0, 5, 'ball', NULL, 'R', 'R', 0, 0);
INSERT INTO statcast_pitches VALUES (19, 1002, DATE '2024-04-02', 1, 2, 434378, 'Verlander, Justin', 111111, 'Batter 4', 1, 'CU', 79.0, 5, 'called_strike', NULL, 'R', 'R', 1, 0);
INSERT INTO statcast_pitches VALUES (20, 1002, DATE '2024-04-02', 1, 3, 434378, 'Verlander, Justin', 111111, 'Batter 4', 1, 'FF', 95.0, 5, 'in_play', 'flyout', 'R', 'R', 1, 1);

INSERT INTO statcast_pitches VALUES (21, 1003, DATE '2024-04-03', 1, 1, 453286, 'Scherzer, Max', 222222, 'Batter 5', 1, 'SI', 93.0, 5, 'ball', NULL, 'R', 'R', 0, 0);
INSERT INTO statcast_pitches VALUES (22, 1003, DATE '2024-04-03', 1, 2, 453286, 'Scherzer, Max', 222222, 'Batter 5', 1, 'CH', 84.0, 5, 'swinging_strike', NULL, 'R', 'R', 1, 0);
INSERT INTO statcast_pitches VALUES (23, 1003, DATE '2024-04-03', 1, 3, 453286, 'Scherzer, Max', 222222, 'Batter 5', 1, 'FF', 94.0, 5, 'in_play', 'lineout', 'R', 'R', 1, 1);

COMMIT;
EXIT;
EOSQL
echo "Sample data inserted successfully"

# Ensure SQL Developer has a connection for this schema
ensure_hr_connection "Baseball Ops" "baseball_ops" "Statcast2024"

# Wait for Oracle SQL Developer to be ready
echo "Focusing SQL Developer window..."
sleep 2
WID=$(DISPLAY=:1 wmctrl -l | grep -iE "sql developer|oracle sql" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="