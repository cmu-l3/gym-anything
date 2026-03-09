#!/bin/bash
set -e
echo "=== Exporting Create Log Recorder Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

RESULT_FILE="/tmp/task_result.json"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Query Jenkins Script Console for log recorder details using Groovy
# This is the most reliable way to get internal configuration
echo "Querying Jenkins for log recorder configuration..."
GROOVY_OUTPUT=$(curl -s -u "$JENKINS_USER:$JENKINS_PASS" \
  --data-urlencode 'script=
import groovy.json.JsonBuilder
import jenkins.model.Jenkins
import java.util.logging.*

def result = [:]
def targetName = "git-debug-recorder"

// Find the specific recorder
def target = Jenkins.instance.log.recorders.find { it.name == targetName }

result.target_found = (target != null)
result.target_name = targetName
result.target_loggers = []

if (target) {
    target.loggers.each { logger ->
        result.target_loggers << [
            name: logger.name,
            level: logger.level?.toString() ?: "null"
        ]
    }
}

result.total_recorder_count = Jenkins.instance.log.recorders.size()
println new JsonBuilder(result).toPrettyString()
' "$JENKINS_URL/scriptText" 2>/dev/null)

# Verify HTTP endpoint accessibility (secondary check)
# The recorder usually exposes a URL like /log/recorder-name/
RECORDER_URL_SLUG="git-debug-recorder"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$JENKINS_USER:$JENKINS_PASS" \
  "$JENKINS_URL/log/$RECORDER_URL_SLUG/" 2>/dev/null || echo "000")

# Load initial state
INITIAL_STATE=$(cat /tmp/initial_recorder_state.txt 2>/dev/null || echo "unknown")

# Parse Groovy output and combine with other signals
# We use Python to robustly construct the final JSON
python3 -c "
import json
import sys

try:
    groovy_raw = '''${GROOVY_OUTPUT}'''
    # Find JSON start in case of noise
    json_start = groovy_raw.find('{')
    if json_start != -1:
        groovy_data = json.loads(groovy_raw[json_start:])
    else:
        groovy_data = {'target_found': False, 'error': 'No JSON in groovy output'}
except Exception as e:
    groovy_data = {'target_found': False, 'error': str(e)}

result = {
    'groovy_data': groovy_data,
    'http_endpoint_code': '${HTTP_CODE}',
    'initial_state': '''${INITIAL_STATE}''',
    'task_start_time': ${TASK_START_TIME},
    'export_timestamp': '$(date -Iseconds)'
}

with open('${RESULT_FILE}', 'w') as f:
    json.dump(result, f, indent=2)

print('Exported JSON summary:')
print(json.dumps(result, indent=2))
"

# Set permissions
chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "=== Export complete ==="