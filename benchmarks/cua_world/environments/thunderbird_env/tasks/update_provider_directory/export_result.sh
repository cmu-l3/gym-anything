#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Check if application was running
APP_RUNNING=$(pgrep -f "thunderbird" > /dev/null && echo "true" || echo "false")

# Take a final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Extract the Address Book Database state programmatically
cat > /tmp/export_db.py << 'EOF'
import sqlite3
import json
import os

db_path = "/home/ga/.thunderbird/default-release/abook.sqlite"
result = {
    "total_contacts": 0,
    "vance_exists": False,
    "jenkins_found": False,
    "jenkins_details": {}
}

if os.path.exists(db_path):
    try:
        conn = sqlite3.connect(db_path)
        c = conn.cursor()
        
        c.execute("SELECT card, name, value FROM properties")
        cards = {}
        for card, name, value in c.fetchall():
            if card not in cards:
                cards[card] = {}
            cards[card][name] = value

        result["total_contacts"] = len(cards)

        for card_id, props in cards.items():
            # Check if Vance is still in the address book
            fname = props.get('FirstName', '')
            lname = props.get('LastName', '')
            dname = props.get('DisplayName', '')
            
            if fname and lname and 'robert' in fname.lower() and 'vance' in lname.lower():
                result["vance_exists"] = True
            elif dname and 'robert vance' in dname.lower():
                result["vance_exists"] = True
                
            # Check if Jenkins was created
            email = props.get('PrimaryEmail', '').lower()
            if 's.jenkins@synthea.example.com' in email:
                result["jenkins_found"] = True
                result["jenkins_details"] = props

        conn.close()
    except Exception as e:
        result["error"] = str(e)

with open("/tmp/db_result.json", "w") as f:
    json.dump(result, f)
EOF

python3 /tmp/export_db.py

# Create final JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
DB_RESULT=$(cat /tmp/db_result.json 2>/dev/null || echo "{}")

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "db_result": $DB_RESULT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final accessible location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="