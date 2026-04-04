#!/bin/bash
set -e
echo "=== Exporting create_crm_email_template task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_template_count.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the database for the created template
# We look for the exact name specified in the task
echo "Querying database for template..."

# Fetch details of the template if it exists
# We join with ir_model to get the human-readable model name (e.g., 'crm.lead')
TEMPLATE_DATA=$(docker exec odoo-db psql -U odoo -d odoodb -t -A -c "
    SELECT 
        mt.name, 
        im.model, 
        mt.subject, 
        mt.body_html, 
        mt.create_date,
        mt.write_date
    FROM mail_template mt
    LEFT JOIN ir_model im ON mt.model_id = im.id
    WHERE mt.name = 'Opportunity Follow-Up';
" 2>/dev/null || echo "")

# Count total templates now
CURRENT_COUNT=$(odoo_db_query "SELECT count(*) FROM mail_template;" 2>/dev/null || echo "0")

# Parse the SQL output (pipe-delimited by default for -A, but body_html might contain pipes)
# To be safer, we'll fetch fields individually or use a custom separator if needed.
# For simplicity in bash, we'll do separate queries or Python parsing. 
# Let's use Python for robust extraction.

python3 - <<PYEOF
import json
import subprocess
import time

def get_query_result(query):
    cmd = ["docker", "exec", "odoo-db", "psql", "-U", "odoo", "-d", "odoodb", "-t", "-A", "-c", query]
    try:
        return subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode('utf-8').strip()
    except:
        return ""

task_start = $TASK_START
initial_count = int("$INITIAL_COUNT") if "$INITIAL_COUNT".isdigit() else 0
current_count = int("$CURRENT_COUNT") if "$CURRENT_COUNT".isdigit() else 0

result = {
    "task_start": task_start,
    "initial_count": initial_count,
    "current_count": current_count,
    "template_found": False,
    "template_name": "",
    "model": "",
    "subject": "",
    "body_html": "",
    "created_recently": False
}

# Check if template exists
name_check = get_query_result("SELECT name FROM mail_template WHERE name = 'Opportunity Follow-Up'")
if name_check == 'Opportunity Follow-Up':
    result['template_found'] = True
    result['template_name'] = name_check
    
    # Get Model
    result['model'] = get_query_result("SELECT im.model FROM mail_template mt JOIN ir_model im ON mt.model_id = im.id WHERE mt.name = 'Opportunity Follow-Up'")
    
    # Get Subject
    result['subject'] = get_query_result("SELECT subject FROM mail_template WHERE name = 'Opportunity Follow-Up'")
    
    # Get Body (handled carefully to avoid shell issues with HTML)
    # We fetch it and let Python handle the string
    result['body_html'] = get_query_result("SELECT body_html FROM mail_template WHERE name = 'Opportunity Follow-Up'")
    
    # Check creation time (simple check: is write_date > task_start - buffer?)
    # Odoo stores UTC. We'll rely on the count increase + existence as primary anti-gaming for simplicity,
    # but we can check if it was created/modified recently.
    create_date_str = get_query_result("SELECT extract(epoch from create_date) FROM mail_template WHERE name = 'Opportunity Follow-Up'")
    if create_date_str:
        create_ts = float(create_date_str)
        if create_ts > (task_start - 60): # Buffer for clock skew
            result['created_recently'] = True

# Save to JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="