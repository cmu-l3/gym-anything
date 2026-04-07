#!/bin/bash
set -e
echo "=== Setting up Database Replay Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Clean up previous run artifacts
rm -rf /tmp/processed_hl7 2>/dev/null || true
# We don't create the directory; the agent/channel should usually handle it, 
# or we let the File Writer fail if it doesn't create dirs (standard behavior creates them).
# To be safe and avoid permission issues for the Java process, we'll create it with loose permissions.
mkdir -p /tmp/processed_hl7
chmod 777 /tmp/processed_hl7

# Reset Database State
echo "Resetting database table 'integration_queue'..."
docker exec nextgen-postgres psql -U postgres -d mirthdb -c "
DROP TABLE IF EXISTS integration_queue;
CREATE TABLE integration_queue (
    id SERIAL PRIMARY KEY,
    hl7_data TEXT NOT NULL,
    status VARCHAR(20) DEFAULT 'PENDING',
    created_at TIMESTAMP DEFAULT NOW(),
    processed_at TIMESTAMP
);

-- Row 1 (Pending)
INSERT INTO integration_queue (hl7_data, status) VALUES (
'MSH|^~\\&|HIS|HOSP|LIS|LAB|20240310100000||ADT^A01|MSG001|P|2.3\\rEVN|A01|20240310100000\\rPID|1||1001^^^MRN||DOE^JOHN||19800101|M', 'PENDING');

-- Row 2 (Pending)
INSERT INTO integration_queue (hl7_data, status) VALUES (
'MSH|^~\\&|HIS|HOSP|LIS|LAB|20240310100500||ADT^A01|MSG002|P|2.3\\rEVN|A01|20240310100500\\rPID|1||1002^^^MRN||SMITH^JANE||19850505|F', 'PENDING');

-- Row 3 (Processed - Historical)
INSERT INTO integration_queue (hl7_data, status, processed_at) VALUES (
'MSH|^~\\&|HIS|HOSP|LIS|LAB|20240309090000||ADT^A01|MSG000|P|2.3\\rEVN|A01|20240309090000\\rPID|1||1000^^^MRN||OLD^DATA||19700101|M', 'PROCESSED', NOW() - INTERVAL '1 day');

-- Row 4 (Pending)
INSERT INTO integration_queue (hl7_data, status) VALUES (
'MSH|^~\\&|HIS|HOSP|LIS|LAB|20240310101000||ADT^A01|MSG003|P|2.3\\rEVN|A01|20240310101000\\rPID|1||1003^^^MRN||JONES^BOB||19901231|M', 'PENDING');

-- Row 5 (Processed - Historical)
INSERT INTO integration_queue (hl7_data, status, processed_at) VALUES (
'MSH|^~\\&|HIS|HOSP|LIS|LAB|20240309093000||ADT^A01|MSG999|P|2.3\\rEVN|A01|20240309093000\\rPID|1||1999^^^MRN||OLD^ENTRY||19750505|F', 'PROCESSED', NOW() - INTERVAL '1 day');
"

# Record initial counts
INITIAL_PENDING=$(docker exec nextgen-postgres psql -U postgres -d mirthdb -t -A -c "SELECT COUNT(*) FROM integration_queue WHERE status = 'PENDING';")
echo "$INITIAL_PENDING" > /tmp/initial_pending_count.txt
echo "Initial Pending Count: $INITIAL_PENDING"

# Open a terminal with instructions
DISPLAY=:1 gnome-terminal --geometry=100x30+50+50 -- bash -c '
echo "======================================================="
echo " NextGen Connect - Database Driven Message Replay"
echo "======================================================="
echo ""
echo "TASK: Process pending messages from the database."
echo ""
echo "Database Connection:"
echo "  URL: jdbc:postgresql://nextgen-postgres:5432/mirthdb"
echo "  User: postgres"
echo "  Pass: postgres"
echo ""
echo "Table: integration_queue"
echo "  Columns: id, hl7_data, status, created_at, processed_at"
echo ""
echo "Goal:"
echo "  1. Poll for status = PENDING"
echo "  2. Write HL7 to /tmp/processed_hl7/\${id}.hl7"
echo "  3. Update record: status = PROCESSED, processed_at = NOW()"
echo ""
echo "Tools:"
echo "  Check DB: docker exec nextgen-postgres psql -U postgres -d mirthdb -c \"SELECT * FROM integration_queue;\""
echo "  Check Files: ls -l /tmp/processed_hl7/"
echo ""
exec bash
' 2>/dev/null &

# Wait for window
sleep 2
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="