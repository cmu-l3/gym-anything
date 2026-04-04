#!/bin/bash
echo "=== Setting up Java 8 to Java 17 Migration Task ==="
source /workspace/scripts/task_utils.sh

# Copy project to home directory
echo "[SETUP] Copying legacy-hr-system to /home/ga/..."
rm -rf /home/ga/legacy-hr-system
cp -r /workspace/data/legacy-hr-system /home/ga/legacy-hr-system
chown -R ga:ga /home/ga/legacy-hr-system

# Record start timestamp
date +%s > /tmp/task_start_timestamp
echo "Task started at: $(cat /tmp/task_start_timestamp)"

# Baseline: count legacy API usages
INITIAL_DATE_COUNT=$(grep -r "java\.util\.Date\|java\.util\.Calendar\|SimpleDateFormat" \
    /home/ga/legacy-hr-system/src/main/java/ 2>/dev/null | wc -l)
echo "$INITIAL_DATE_COUNT" > /tmp/initial_date_count
echo "Initial Date/Calendar usage count: $INITIAL_DATE_COUNT"

INITIAL_RAWTYPE_COUNT=$(grep -rn "Map employees\|Map departments\|List result\|List results\|List bonuses\|List getAnnual\|List getLong\|List generateHead\|List generateSalary\|List employees" \
    /home/ga/legacy-hr-system/src/main/java/ 2>/dev/null | wc -l)
echo "$INITIAL_RAWTYPE_COUNT" > /tmp/initial_rawtype_count
echo "Initial raw type count: $INITIAL_RAWTYPE_COUNT"

INITIAL_STRINGBUFFER=$(grep -r "StringBuffer" /home/ga/legacy-hr-system/src/main/java/ 2>/dev/null | wc -l)
echo "$INITIAL_STRINGBUFFER" > /tmp/initial_stringbuffer_count
echo "Initial StringBuffer count: $INITIAL_STRINGBUFFER"

# Ensure Eclipse is running
ensure_display_ready

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
