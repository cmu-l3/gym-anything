#!/bin/bash
echo "=== Exporting Test Suite Execution Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)
PROJECT_ROOT="/opt/openice/mdpnp"

# 1. Locate generated test result artifacts (XMLs)
# Find directories containing test-results created/modified after start time
echo "Searching for test artifacts..."
# We look for xml files modified after task start
TEST_XML_FILES=$(find "$PROJECT_ROOT" -path "*/build/test-results/test/TEST-*.xml" -newermt "@$TASK_START" 2>/dev/null)
XML_COUNT=$(echo "$TEST_XML_FILES" | grep -c "xml" || echo "0")

# 2. Parse XMLs to get aggregate statistics
TOTAL_TESTS=0
TOTAL_FAILURES=0
TOTAL_ERRORS=0
TOTAL_SKIPPED=0
MODULES_FOUND=""

if [ "$XML_COUNT" -gt 0 ]; then
    echo "Found $XML_COUNT new test result XML files."
    
    # Simple Python parser to aggregate stats from standard JUnit XML format
    # <testsuite tests="X" failures="Y" errors="Z" skipped="W" ...>
    STATS_JSON=$(python3 -c "
import xml.etree.ElementTree as ET
import sys
import os
import json

files = sys.stdin.read().splitlines()
stats = {'tests': 0, 'failures': 0, 'errors': 0, 'skipped': 0, 'modules': set()}

for f in files:
    if not f.strip(): continue
    try:
        # Extract module name from path (e.g., .../demo-apps/build/...)
        parts = f.split('/')
        if 'build' in parts:
            idx = parts.index('build')
            if idx > 0:
                stats['modules'].add(parts[idx-1])
                
        tree = ET.parse(f)
        root = tree.getroot()
        # Handle both testsuite root and testsuites root
        if root.tag == 'testsuites':
            suites = root.findall('testsuite')
        else:
            suites = [root]
            
        for suite in suites:
            stats['tests'] += int(suite.get('tests', 0))
            stats['failures'] += int(suite.get('failures', 0))
            stats['errors'] += int(suite.get('errors', 0))
            stats['skipped'] += int(suite.get('skipped', 0))
    except Exception as e:
        sys.stderr.write(f'Error parsing {f}: {e}\n')

stats['modules'] = list(stats['modules'])
print(json.dumps(stats))
" <<< "$TEST_XML_FILES")

    TOTAL_TESTS=$(echo "$STATS_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['tests'])")
    TOTAL_FAILURES=$(echo "$STATS_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['failures'])")
    TOTAL_ERRORS=$(echo "$STATS_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['errors'])")
    TOTAL_SKIPPED=$(echo "$STATS_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['skipped'])")
    MODULES_FOUND=$(echo "$STATS_JSON" | python3 -c "import sys, json; print(','.join(json.load(sys.stdin)['modules']))")
fi

# 3. Check the report file
REPORT_PATH="/home/ga/Desktop/test_execution_report.txt"
REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_CONTENT=""

if [ -f "$REPORT_PATH" ]; then
    # Check if modified after task start
    R_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$R_MTIME" -gt "$TASK_START" ]; then
        REPORT_EXISTS="true"
        REPORT_SIZE=$(stat -c %s "$REPORT_PATH")
        # Read content for verification (limit size)
        REPORT_CONTENT=$(cat "$REPORT_PATH" | head -c 5000)
    fi
fi

# 4. Get Git Commit Info (Ground Truth)
cd "$PROJECT_ROOT"
GIT_COMMIT_HASH=$(git log --oneline -1 | cut -d' ' -f1)

# Create result JSON
# Use a temp file and copy to ensure permissions
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "xml_files_found": $XML_COUNT,
    "modules_tested": "$MODULES_FOUND",
    "stats_from_xml": {
        "tests": $TOTAL_TESTS,
        "failures": $TOTAL_FAILURES,
        "errors": $TOTAL_ERRORS,
        "skipped": $TOTAL_SKIPPED
    },
    "report": {
        "exists": $REPORT_EXISTS,
        "size": $REPORT_SIZE,
        "content_snippet": $(python3 -c "import json, sys; print(json.dumps(sys.stdin.read()))" <<< "$REPORT_CONTENT")
    },
    "ground_truth": {
        "git_hash": "$GIT_COMMIT_HASH"
    }
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="
echo "XML Files: $XML_COUNT"
echo "Tests Run: $TOTAL_TESTS"
echo "Report Exists: $REPORT_EXISTS"
cat /tmp/task_result.json