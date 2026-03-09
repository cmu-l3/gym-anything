#!/bin/bash
echo "=== Exporting trust_safety_reviewer_suspension result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Helper function to run SQL and output raw JSON result
query_json() {
    orientdb_sql "demodb" "$1"
}

# 1. Check Schema (AccountStatus on Profiles)
# We check if the property exists in the class definition
SCHEMA_JSON=$(curl -s -u "${ORIENTDB_AUTH}" "${ORIENTDB_URL}/database/demodb")

# 2. Check Bot Statuses
# Bot Alpha (Expected: Suspended)
BOT_ALPHA_STATUS=$(query_json "SELECT AccountStatus FROM Profiles WHERE Email='bot.alpha@spamnet.com'")

# Bot Beta (Expected: Suspended)
BOT_BETA_STATUS=$(query_json "SELECT AccountStatus FROM Profiles WHERE Email='bot.beta@spamnet.com'")

# Innocent User (Expected: NULL or not 'Suspended')
INNOCENT_STATUS=$(query_json "SELECT AccountStatus FROM Profiles WHERE Email='innocent.user@normal.com'")

# 3. Check Logs and Edges
# We check if bots have outgoing HasSuspensionLog edges to a SuspensionLog vertex
# Returns the count of edges and the Reason property of the connected vertex
BOT_ALPHA_LOG=$(query_json "SELECT out('HasSuspensionLog').Reason as Reasons FROM Profiles WHERE Email='bot.alpha@spamnet.com'")
BOT_BETA_LOG=$(query_json "SELECT out('HasSuspensionLog').Reason as Reasons FROM Profiles WHERE Email='bot.beta@spamnet.com'")

# Create Python script to assemble the JSON cleanly
# We pipe the raw JSON strings into python to parse and restructure
python3 -c "
import sys, json, time

try:
    schema = json.loads('''${SCHEMA_JSON}''')
    bot_alpha_res = json.loads('''${BOT_ALPHA_STATUS}''')
    bot_beta_res = json.loads('''${BOT_BETA_STATUS}''')
    innocent_res = json.loads('''${INNOCENT_STATUS}''')
    alpha_log_res = json.loads('''${BOT_ALPHA_LOG}''')
    beta_log_res = json.loads('''${BOT_BETA_LOG}''')
except Exception as e:
    print(json.dumps({'error': str(e)}))
    sys.exit(1)

# Analyze Schema
classes = {c['name']: c for c in schema.get('classes', [])}
profiles_props = [p['name'] for p in classes.get('Profiles', {}).get('properties', [])]
has_account_status = 'AccountStatus' in profiles_props
has_suspension_log_class = 'SuspensionLog' in classes
has_edge_class = 'HasSuspensionLog' in classes

# Analyze Data
def get_val(res, key):
    rows = res.get('result', [])
    if not rows: return None
    return rows[0].get(key)

bot_alpha_status = get_val(bot_alpha_res, 'AccountStatus')
bot_beta_status = get_val(bot_beta_res, 'AccountStatus')
innocent_status = get_val(innocent_res, 'AccountStatus')

# Analyze Logs (The result is a list of Reasons, e.g. ['Review Bombing'])
alpha_reasons = get_val(alpha_log_res, 'Reasons') or []
beta_reasons = get_val(beta_log_res, 'Reasons') or []

result = {
    'schema': {
        'has_account_status': has_account_status,
        'has_suspension_log_class': has_suspension_log_class,
        'has_edge_class': has_edge_class
    },
    'data': {
        'bot_alpha_status': bot_alpha_status,
        'bot_beta_status': bot_beta_status,
        'innocent_status': innocent_status
    },
    'logs': {
        'bot_alpha_reasons': alpha_reasons,
        'bot_beta_reasons': beta_reasons
    },
    'timestamp': int(time.time()),
    'task_duration': $TASK_END - $TASK_START
}

print(json.dumps(result, indent=2))
" > /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="