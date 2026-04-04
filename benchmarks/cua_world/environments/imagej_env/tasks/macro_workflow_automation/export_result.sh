#!/bin/bash
source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Macro Workflow Result ==="

MACRO_PATH="/home/ga/ImageJ_Data/macros/standard_protocol.ijm"
TEST_RESULT_CSV="/tmp/verification_results.csv"
TEST_LOG="/tmp/macro_test.log"

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check file metadata
FILE_EXISTS="false"
FILE_SIZE=0
FILE_CONTENT=""
MACRO_WORKS="false"
PARTICLE_COUNT=0

if [ -f "$MACRO_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$MACRO_PATH")
    # Read content, escaping backslashes and double quotes for JSON
    FILE_CONTENT=$(cat "$MACRO_PATH" | python3 -c 'import sys, json; print(json.dumps(sys.stdin.read()))')
    # Remove outer quotes added by json.dumps since we'll insert it into json template
    FILE_CONTENT=${FILE_CONTENT:1:-1} 
    
    echo "Macro file found. Size: $FILE_SIZE bytes"
    
    # 2. Functional Verification
    # We attempt to run the agent's macro on a fresh Blobs image using headless Fiji
    # Since the task asks to record steps *after* opening the image, 
    # the macro likely works on the "current" image.
    
    echo "Running functional verification..."
    
    # Create a verification wrapper script
    VERIFY_SCRIPT="/tmp/verify_agent_macro.ijm"
    cat > "$VERIFY_SCRIPT" << EOF
// Verification Wrapper
setBatchMode(true);
try {
    run("Blobs (25K)");
    // Run the agent's macro
    runMacro("$MACRO_PATH");
    // Save results if generated
    if (nResults > 0) {
        saveAs("Results", "$TEST_RESULT_CSV");
    } else {
        // Create empty file to signal no results
        File.saveString("No results", "$TEST_RESULT_CSV");
    }
} catch(e) {
    print("Error: " + e);
}
setBatchMode(false);
eval("script", "System.exit(0);");
EOF

    # Find Fiji
    FIJI_EXEC=$(find_fiji_executable)
    if [ -n "$FIJI_EXEC" ]; then
        # Run headless
        "$FIJI_EXEC" --headless -macro "$VERIFY_SCRIPT" > "$TEST_LOG" 2>&1
        
        # Check if results were generated
        if [ -f "$TEST_RESULT_CSV" ]; then
            # Count data rows (excluding header)
            LINE_COUNT=$(wc -l < "$TEST_RESULT_CSV")
            if [ "$LINE_COUNT" -gt 1 ]; then
                MACRO_WORKS="true"
                PARTICLE_COUNT=$((LINE_COUNT - 1))
            fi
        fi
    fi
fi

# Get timestamp info
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
FILE_MTIME=0
if [ -f "$MACRO_PATH" ]; then
    FILE_MTIME=$(stat -c %Y "$MACRO_PATH")
fi

# 3. Create Result JSON
# Using python to ensure safe JSON generation
python3 << PYEOF
import json
import os

result = {
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_path": "$MACRO_PATH",
    "file_size": $FILE_SIZE,
    "file_mtime": $FILE_MTIME,
    "macro_content": "$FILE_CONTENT",
    "functional_test": {
        "success": $MACRO_WORKS,
        "particle_count": $PARTICLE_COUNT,
        "log_path": "$TEST_LOG"
    },
    "screenshot_path": "/tmp/task_final.png"
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json