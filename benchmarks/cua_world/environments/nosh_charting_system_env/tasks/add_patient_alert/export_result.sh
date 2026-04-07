#!/bin/bash
echo "=== Exporting add_patient_alert results ==="

# 1. Capture Final Screenshot (Evidence)
DISPLAY=:1 scrot /tmp/task_final.png || true

# 2. Get Task Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_alert_count.txt 2>/dev/null || echo "0")
PATIENT_PID=9901

# 3. Query Database for Alerts
# We fetch specific fields to verify content and timing
# UNIX_TIMESTAMP(alert_date) helps compare against task start
echo "Querying alerts..."
SQL_QUERY="SELECT alert, alert_date_inactive, UNIX_TIMESTAMP(created_date) 
           FROM alerts 
           WHERE pid = $PATIENT_PID;"

# Execute query via Docker
QUERY_RESULT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "$SQL_QUERY" 2>/dev/null)

# 4. Process Results
# We might have multiple alerts (though unlikely if agent followed instructions). 
# We'll export all of them as a JSON array.

# Create a temporary python script to format the SQL output as JSON
# This avoids fragile bash string parsing
cat <<EOF > /tmp/format_results.py
import json
import sys
import time

try:
    raw_data = sys.stdin.read().strip()
    alerts = []
    
    if raw_data:
        rows = raw_data.split('\n')
        for row in rows:
            parts = row.split('\t')
            if len(parts) >= 3:
                alert_text = parts[0]
                inactive_date = parts[1] if parts[1] != 'NULL' else None
                created_ts = int(parts[2]) if parts[2] != 'NULL' else 0
                
                alerts.append({
                    "text": alert_text,
                    "is_active": (inactive_date is None),
                    "created_timestamp": created_ts
                })
    
    output = {
        "task_start_timestamp": int($TASK_START),
        "initial_count": int($INITIAL_COUNT),
        "current_count": len(alerts),
        "alerts": alerts,
        "screenshot_exists": True
    }
    
    print(json.dumps(output, indent=2))

except Exception as e:
    # Fallback JSON
    print(json.dumps({"error": str(e), "alerts": []}))
EOF

# Run the python formatter with query result
echo "$QUERY_RESULT" | python3 /tmp/format_results.py > /tmp/task_result.json

# Cleanup
rm /tmp/format_results.py

# Secure the result file
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json