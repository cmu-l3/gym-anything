#!/bin/bash
echo "=== Exporting Record Family History Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create final database dump to evaluate state changes
echo "Creating final database dump..."
mysqldump -u freemed -pfreemed freemed --skip-extended-insert --no-create-info --compact > /tmp/freemed_after.sql 2>/dev/null || true

# Analyze dumps using Python
echo "Analyzing database state delta..."
python3 << 'EOF'
import json, os, re

result = {
    "phrase_found_after": False,
    "phrase_found_before": False,
    "table_name": None,
    "initial_count": 0,
    "final_count": 0,
    "phrase_matches": [],
    "app_running": False
}

# The target phrase we required the agent to input
phrase = "myocardial infarction at age 55".lower()

# Check initial dump for phrase (should not exist)
before_matches = []
if os.path.exists("/tmp/freemed_before.sql"):
    with open("/tmp/freemed_before.sql", "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            if phrase in line.lower():
                before_matches.append(line.strip())

result["phrase_found_before"] = len(before_matches) > 0

# Check final dump for phrase
after_matches = []
table_name = None
if os.path.exists("/tmp/freemed_after.sql"):
    with open("/tmp/freemed_after.sql", "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            if phrase in line.lower():
                after_matches.append(line.strip())
                # Extract the table name from the INSERT statement dynamically
                m = re.search(r'INSERT INTO `([^`]+)`', line)
                if m and not table_name:
                    table_name = m.group(1)

result["phrase_found_after"] = len(after_matches) > 0
result["phrase_matches"] = after_matches
result["table_name"] = table_name

# If a table name was found, count its total rows before and after to verify discrete insertion
if table_name:
    if os.path.exists("/tmp/freemed_before.sql"):
        with open("/tmp/freemed_before.sql", "r", encoding="utf-8", errors="ignore") as f:
            result["initial_count"] = sum(1 for line in f if f"INSERT INTO `{table_name}`" in line)
    
    if os.path.exists("/tmp/freemed_after.sql"):
        with open("/tmp/freemed_after.sql", "r", encoding="utf-8", errors="ignore") as f:
            result["final_count"] = sum(1 for line in f if f"INSERT INTO `{table_name}`" in line)

# Check if application was running
result["app_running"] = os.system("pgrep -f firefox > /dev/null") == 0

# Save output
with open("/tmp/family_history_result.json", "w") as f:
    json.dump(result, f)
EOF

# Handle permissions safely
chmod 666 /tmp/family_history_result.json 2>/dev/null || sudo chmod 666 /tmp/family_history_result.json 2>/dev/null || true

echo "Result JSON saved:"
cat /tmp/family_history_result.json
echo ""
echo "=== Export complete ==="