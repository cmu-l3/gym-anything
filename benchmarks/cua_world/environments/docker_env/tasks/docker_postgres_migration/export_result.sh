#!/bin/bash
echo "=== Exporting Docker PostgreSQL Migration Result ==="
source /workspace/scripts/task_utils.sh

take_screenshot "migration_task_end"

# ── Read baseline ──────────────────────────────────────────────────────────────
TASK_START=0
if [ -f /tmp/task_start_timestamp ]; then
    TASK_START=$(cat /tmp/task_start_timestamp)
fi

# ── Read PG13 baseline counts ─────────────────────────────────────────────────
PG13_COUNTS_FILE="/tmp/initial_pg13_counts.json"
PG13_ARTIST=0; PG13_EMPLOYEE=0; PG13_CUSTOMER=0; PG13_TOTAL=0
if [ -f "$PG13_COUNTS_FILE" ]; then
    PG13_ARTIST=$(python3 -c "import json; d=json.load(open('$PG13_COUNTS_FILE')); print(d.get('Artist',0))" 2>/dev/null || echo 0)
    PG13_EMPLOYEE=$(python3 -c "import json; d=json.load(open('$PG13_COUNTS_FILE')); print(d.get('Employee',0))" 2>/dev/null || echo 0)
    PG13_CUSTOMER=$(python3 -c "import json; d=json.load(open('$PG13_COUNTS_FILE')); print(d.get('Customer',0))" 2>/dev/null || echo 0)
    PG13_TRACK=$(python3 -c "import json; d=json.load(open('$PG13_COUNTS_FILE')); print(d.get('Track',0))" 2>/dev/null || echo 0)
fi

# ── Check PG15 container ──────────────────────────────────────────────────────
PG15_RUNNING=0
PG15_CREATED_AT=0
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^chinook-pg15$"; then
    PG15_RUNNING=1
    # Get container creation time in epoch seconds
    CREATED_ISO=$(docker inspect chinook-pg15 --format '{{.Created}}' 2>/dev/null || echo "")
    if [ -n "$CREATED_ISO" ]; then
        PG15_CREATED_AT=$(python3 -c "
import datetime, sys
s = '$CREATED_ISO'.split('.')[0].replace('T', ' ')
try:
    dt = datetime.datetime.strptime(s, '%Y-%m-%d %H:%M:%S')
    import calendar
    print(int(calendar.timegm(dt.timetuple())))
except:
    print(0)
" 2>/dev/null || echo 0)
    fi
fi

PG15_CREATED_AFTER_START=0
if [ "$PG15_CREATED_AT" -gt "$TASK_START" ] 2>/dev/null; then
    PG15_CREATED_AFTER_START=1
fi

# ── Query PG15 for database existence and row counts ─────────────────────────
pg15_query() {
    docker exec chinook-pg15 psql -U chinook -d chinook -t -c "$1" 2>/dev/null | tr -d ' \n'
}

PG15_DB_ACCESSIBLE=0
PG15_ARTIST=0
PG15_EMPLOYEE=0
PG15_CUSTOMER=0
PG15_TRACK=0

# Check tables present
PG15_TABLES_JSON="[]"
PG15_TABLE_COUNT=0

if [ "$PG15_RUNNING" = "1" ]; then
    # Try to ping the database
    if docker exec chinook-pg15 pg_isready -U chinook -d chinook 2>/dev/null; then
        PG15_DB_ACCESSIBLE=1

        # Get row counts (use 0 as fallback)
        PG15_ARTIST=$(pg15_query 'SELECT COUNT(*) FROM "Artist"' 2>/dev/null || echo 0)
        PG15_EMPLOYEE=$(pg15_query 'SELECT COUNT(*) FROM "Employee"' 2>/dev/null || echo 0)
        PG15_CUSTOMER=$(pg15_query 'SELECT COUNT(*) FROM "Customer"' 2>/dev/null || echo 0)
        PG15_TRACK=$(pg15_query 'SELECT COUNT(*) FROM "Track"' 2>/dev/null || echo 0)

        PG15_ARTIST=${PG15_ARTIST:-0}
        PG15_EMPLOYEE=${PG15_EMPLOYEE:-0}
        PG15_CUSTOMER=${PG15_CUSTOMER:-0}
        PG15_TRACK=${PG15_TRACK:-0}

        # Get all table names from information_schema
        TABLES_RAW=$(docker exec chinook-pg15 psql -U chinook -d chinook -t -c \
            "SELECT table_name FROM information_schema.tables WHERE table_schema='public' ORDER BY table_name;" \
            2>/dev/null || echo "")

        if [ -n "$TABLES_RAW" ]; then
            PG15_TABLE_COUNT=$(echo "$TABLES_RAW" | grep -vc '^[[:space:]]*$' || echo 0)
            PG15_TABLES_JSON=$(echo "$TABLES_RAW" | grep -v '^[[:space:]]*$' | \
                python3 -c "import sys,json; lines=[l.strip() for l in sys.stdin if l.strip()]; print(json.dumps(lines))" 2>/dev/null || echo '[]')
        fi
    fi
fi

# ── Count matching tables from expected set ────────────────────────────────────
EXPECTED_TABLES='["Artist","Album","Track","Customer","Employee","Invoice","InvoiceLine","Playlist","PlaylistTrack","MediaType","Genre"]'
TABLES_MATCHED=$(python3 -c "
import json
expected = json.loads('$EXPECTED_TABLES')
present_json = '''$PG15_TABLES_JSON'''
try:
    present = json.loads(present_json)
except:
    present = []
present_lower = [t.lower() for t in present]
matched = sum(1 for t in expected if t.lower() in present_lower)
print(matched)
" 2>/dev/null || echo 0)

# ── Row count comparison ──────────────────────────────────────────────────────
ARTIST_MATCH=0
EMPLOYEE_MATCH=0
CUSTOMER_MATCH=0

if [ "$PG13_ARTIST" -gt 0 ] && [ "$PG15_ARTIST" = "$PG13_ARTIST" ] 2>/dev/null; then ARTIST_MATCH=1; fi
if [ "$PG13_EMPLOYEE" -gt 0 ] && [ "$PG15_EMPLOYEE" = "$PG13_EMPLOYEE" ] 2>/dev/null; then EMPLOYEE_MATCH=1; fi
if [ "$PG13_CUSTOMER" -gt 0 ] && [ "$PG15_CUSTOMER" = "$PG13_CUSTOMER" ] 2>/dev/null; then CUSTOMER_MATCH=1; fi

# ── Write result JSON ──────────────────────────────────────────────────────────
cat > /tmp/docker_migration_result.json <<EOF
{
  "task_start": ${TASK_START},
  "pg15_running": ${PG15_RUNNING},
  "pg15_db_accessible": ${PG15_DB_ACCESSIBLE},
  "pg15_created_at": ${PG15_CREATED_AT},
  "pg15_created_after_start": ${PG15_CREATED_AFTER_START},
  "pg13_artist_count": ${PG13_ARTIST},
  "pg13_employee_count": ${PG13_EMPLOYEE},
  "pg13_customer_count": ${PG13_CUSTOMER},
  "pg13_track_count": ${PG13_TRACK:-0},
  "pg15_artist_count": ${PG15_ARTIST},
  "pg15_employee_count": ${PG15_EMPLOYEE},
  "pg15_customer_count": ${PG15_CUSTOMER},
  "pg15_track_count": ${PG15_TRACK},
  "artist_count_match": ${ARTIST_MATCH},
  "employee_count_match": ${EMPLOYEE_MATCH},
  "customer_count_match": ${CUSTOMER_MATCH},
  "pg15_table_count": ${PG15_TABLE_COUNT},
  "expected_tables_matched": ${TABLES_MATCHED},
  "pg15_tables": ${PG15_TABLES_JSON}
}
EOF

echo "=== Export Complete ==="
echo "Result saved to /tmp/docker_migration_result.json"
cat /tmp/docker_migration_result.json
