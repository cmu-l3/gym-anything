#!/bin/bash
echo "=== Exporting generate_alert_from_failed_check result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_CHECK_ID=$(cat /tmp/target_check_id.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if application is running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Query Odoo to get the final state of the specific check and any linked alerts
python3 << PYTHON_EOF
import xmlrpc.client
import json
import sys
import datetime

url = "http://localhost:8069"
db = "odoo_quality"
pwd = "admin"
target_check_id = int("$TARGET_CHECK_ID")
task_start = int("$TASK_START")

result = {
    "check_found": False,
    "alert_created": False,
    "alert_linked": False,
    "alert_title": None,
    "alert_tags": [],
    "alert_create_date_timestamp": 0,
    "check_data": {},
    "alert_data": {}
}

try:
    if target_check_id == 0:
        raise ValueError("No target check ID found")

    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, "admin", pwd, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # 1. Fetch the target check
    # We read 'alert_ids' (if one2many) or check if we can find an alert with check_id = target
    checks = models.execute_kw(db, uid, pwd, 'quality.check', 'read', [[target_check_id], ['quality_state', 'alert_ids', 'product_id']])
    
    if checks:
        result["check_found"] = True
        check = checks[0]
        result["check_data"] = check
        
        # 2. Check for linked alerts
        # Case A: alert_ids field exists and is populated
        alert_ids = check.get('alert_ids', [])
        
        # Case B: Search quality.alert where check_id matches (inverse relation)
        if not alert_ids:
            found_alerts = models.execute_kw(db, uid, pwd, 'quality.alert', 'search', [[['check_id', '=', target_check_id]]])
            alert_ids = found_alerts

        if alert_ids:
            result["alert_linked"] = True
            # Get the most recently created alert linked to this check
            alerts = models.execute_kw(db, uid, pwd, 'quality.alert', 'read', [alert_ids, ['name', 'tag_ids', 'create_date', 'check_id']])
            
            # Sort by create_date desc? Odoo dates are strings.
            # We'll just take the last one or iterate to find one created after start time
            valid_alert = None
            for a in alerts:
                # Odoo datetime string: '2023-10-25 10:00:00' (UTC)
                cdate_str = a['create_date']
                # Simple parsing
                # If microseconds missing, handle that
                fmt = "%Y-%m-%d %H:%M:%S"
                if "." in cdate_str:
                    fmt = "%Y-%m-%d %H:%M:%S.%f"
                
                try:
                    dt = datetime.datetime.strptime(cdate_str, fmt)
                    # Rough conversion to timestamp (assuming UTC which Odoo uses internally)
                    ts = dt.replace(tzinfo=datetime.timezone.utc).timestamp()
                    
                    if ts > task_start:
                        valid_alert = a
                        result["alert_create_date_timestamp"] = ts
                        break
                except Exception as e:
                    print(f"Date parse error: {e}", file=sys.stderr)
            
            # If we didn't find one by timestamp, just take the first linked one 
            # and let the verifier decide based on timestamp provided
            if not valid_alert and alerts:
                valid_alert = alerts[0]
            
            if valid_alert:
                result["alert_created"] = True
                result["alert_data"] = valid_alert
                result["alert_title"] = valid_alert.get('name')
                
                # Fetch tag names
                tag_ids = valid_alert.get('tag_ids', [])
                if tag_ids:
                    tags = models.execute_kw(db, uid, pwd, 'quality.tag', 'read', [tag_ids, ['name']])
                    result["alert_tags"] = [t['name'] for t in tags]

except Exception as e:
    result["error"] = str(e)
    print(f"Export error: {e}", file=sys.stderr)

# Write result
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)

print(json.dumps(result, indent=2))
PYTHON_EOF

# Secure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="