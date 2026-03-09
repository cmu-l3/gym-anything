#!/bin/bash
echo "=== Exporting create_booking_system results ==="

# Timestamp
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Source utilities
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$PATH:$JAVA_HOME/bin
source /workspace/scripts/task_utils.sh

# 1. Check File Output
REPORT_FILE="/home/ga/bookings_report.json"
FILE_EXISTS=false
FILE_SIZE=0
FILE_CREATED_DURING=false

if [ -f "$REPORT_FILE" ]; then
    FILE_EXISTS=true
    FILE_SIZE=$(stat -c %s "$REPORT_FILE")
    FILE_MTIME=$(stat -c %Y "$REPORT_FILE")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING=true
    fi
fi

# 2. Extract Database Schema (to check classes and sequences)
echo "Fetching schema..."
SCHEMA_JSON=$(curl -s -u "${ORIENTDB_AUTH}" "${ORIENTDB_URL}/database/demodb")

# 3. Extract Sequences specifically (API doesn't always show current value in schema)
echo "Fetching sequences..."
SEQUENCES_JSON=$(orientdb_sql "demodb" "SELECT name, value FROM OSequence WHERE name IN ['booking_seq', 'invoice_seq']")

# 4. Extract Bookings Data
echo "Fetching bookings..."
BOOKINGS_JSON=$(orientdb_sql "demodb" "SELECT BookingRef, InvoiceNum, CheckIn, CheckOut, Status, TotalPrice FROM Bookings ORDER BY BookingRef")

# 5. Extract Graph Connections (Edges)
echo "Fetching graph connections..."
# Get HasBooking edges: Profile Email -> Booking Ref
HAS_BOOKING_JSON=$(orientdb_sql "demodb" "SELECT out.Email as GuestEmail, in.BookingRef as BookingRef FROM HasBooking")
# Get BookedAt edges: Booking Ref -> Hotel Name
BOOKED_AT_JSON=$(orientdb_sql "demodb" "SELECT out.BookingRef as BookingRef, in.Name as HotelName FROM BookedAt")

# 6. Take final screenshot
take_screenshot /tmp/task_final.png

# 7. Package everything into result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json
import sys

# Safe loader
def load_json(s):
    try:
        return json.loads(s) if s else {}
    except:
        return {}

schema = load_json('''$SCHEMA_JSON''')
sequences = load_json('''$SEQUENCES_JSON''')
bookings = load_json('''$BOOKINGS_JSON''')
has_booking = load_json('''$HAS_BOOKING_JSON''')
booked_at = load_json('''$BOOKED_AT_JSON''')

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'file_info': {
        'exists': $FILE_EXISTS,
        'size': $FILE_SIZE,
        'created_during_task': $FILE_CREATED_DURING
    },
    'schema': schema,
    'sequences': sequences.get('result', []),
    'bookings': bookings.get('result', []),
    'edges': {
        'has_booking': has_booking.get('result', []),
        'booked_at': booked_at.get('result', [])
    }
}

print(json.dumps(result))
" > "$TEMP_JSON"

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="