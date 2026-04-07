#!/bin/bash
echo "=== Exporting JVM Runtime Forensics Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Basic Variables
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FORENSICS_DIR="/home/ga/Desktop/jvm_forensics"
ACTUAL_PID=$(cat /tmp/ground_truth_pid.txt 2>/dev/null || echo "")

# 3. Check Files
# Function to check file status: exists, size, created_during_task, content_match
check_file() {
    local filename=$1
    local filepath="$FORENSICS_DIR/$filename"
    local required_pattern=$2
    
    local exists=false
    local size=0
    local created_during=false
    local pattern_matched=false
    local content_sample=""

    if [ -f "$filepath" ]; then
        exists=true
        size=$(stat -c %s "$filepath")
        mtime=$(stat -c %Y "$filepath")
        
        if [ "$mtime" -gt "$TASK_START" ]; then
            created_during=true
        fi
        
        if [ -n "$required_pattern" ]; then
            if grep -qE "$required_pattern" "$filepath"; then
                pattern_matched=true
            fi
        else
            pattern_matched=true
        fi
        
        # Get a small sample safely for the JSON
        content_sample=$(head -n 5 "$filepath" | tr '\n' ' ' | sed 's/"/\\"/g' | cut -c 1-200)
    fi
    
    echo "\"file_$filename\": {
        \"exists\": $exists,
        \"size\": $size,
        \"created_during_task\": $created_during,
        \"pattern_matched\": $pattern_matched,
        \"sample\": \"$content_sample\"
    }"
}

# 4. Specific Content Checks
# Heap Stats: Look for column headers like S0, S1, E, O or S0C, S1C
HEAP_STATS_CHECK=$(check_file "heap_stats.txt" "S0|S1|E|O|M|CCS|YGC")

# Thread Dump: Look for Thread.State or "nid="
THREAD_DUMP_CHECK=$(check_file "thread_dump.txt" "java.lang.Thread.State|nid=|prio=")

# JVM Config: Look for -XX flags or java properties
JVM_CONFIG_CHECK=$(check_file "jvm_config.txt" "\-XX:|java\.vm|user\.dir|command_line")

# Heap Summary: Look for generation names or heap config
HEAP_SUMMARY_CHECK=$(check_file "heap_summary.txt" "Heap|Configuration|MinHeap|MaxHeap|Metaspace|generation")

# Performance Report: No regex here, verify in python
REPORT_CHECK=$(check_file "performance_report.txt" "")
# Read report content for Python analysis (full content)
REPORT_CONTENT=""
if [ -f "$FORENSICS_DIR/performance_report.txt" ]; then
    REPORT_CONTENT=$(cat "$FORENSICS_DIR/performance_report.txt" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr '\n' ' ')
fi

# 5. Check if correct PID was analyzed
# Scan files for the actual PID
PID_FOUND_IN_FILES=false
if [ -n "$ACTUAL_PID" ]; then
    if grep -r "$ACTUAL_PID" "$FORENSICS_DIR" > /dev/null 2>&1; then
        PID_FOUND_IN_FILES=true
    fi
fi

# 6. Check if OpenICE is still running
APP_RUNNING=false
if is_openice_running; then
    APP_RUNNING=true
fi

# 7. Construct Result JSON
# Using a temp file to avoid race conditions/permissions
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "ground_truth_pid": "$ACTUAL_PID",
    "pid_found_in_files": $PID_FOUND_IN_FILES,
    "app_running": $APP_RUNNING,
    "files": {
        $HEAP_STATS_CHECK,
        $THREAD_DUMP_CHECK,
        $JVM_CONFIG_CHECK,
        $HEAP_SUMMARY_CHECK,
        $REPORT_CHECK
    },
    "report_content": "$REPORT_CONTENT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="