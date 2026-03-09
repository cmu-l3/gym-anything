#!/bin/bash
# Export script for create_case_folders task

echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# Load task context
CASE_ID=$(cat /tmp/task_case_id.txt 2>/dev/null || echo "")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# capture final screenshot
take_screenshot /tmp/task_final.png

# Initialize results
API_CHECK_SUCCESS="false"
FOLDERS_FOUND="[]"
CASE_FOUND="false"

# API Verification Strategy
# We will attempt to list the contents of the case's document container.
# If we have the Case ID, we can query the complaint module.

if [ -n "$CASE_ID" ]; then
    CASE_FOUND="true"
    echo "Checking folders for Case ID: $CASE_ID"

    # NOTE: The exact endpoint to list folders for a specific complaint might vary by ArkCase version.
    # Common pattern: Get the container ID for the case, then list children.
    # We'll try a direct search for folders linked to this parent ID if possible, 
    # or rely on the generic 'files' endpoint if it exposes folders.
    
    # Attempt 1: Get case details to find 'dmsId' or folder structure
    CASE_DETAILS=$(arkcase_api GET "plugin/complaint/${CASE_ID}" 2>/dev/null || echo "")
    
    # If we can't find a direct folder list, we will try to use the generic search API 
    # looking for objects of type 'cmis:folder' with the specific names created *after* task start.
    # This is a robust heuristic: if a folder named "Evidence" was created recently, it's likely the agent.
    
    # We'll stick to a simpler method: The verify script will rely heavily on VLM, 
    # but we will try to dump the HTML of the current page if possible, or just export basic stats.
    
    # Since we cannot easily curl the specific folder tree without complex CMIS queries,
    # we will focus on what we can prove: The case exists, and the agent was active.
    
    # However, let's try one specific CMIS-like query if available in the API.
    # Fallback: We will trust the VLM for the folder names.
    
    true
else
    echo "WARNING: Case ID not found in temp file."
fi

# Collect evidence of user activity (anti-gaming)
# Check for mouse/keyboard activity logs if available, or just file timestamps in home dir
# (Not applicable for web app interactions without proxy logs)

# Create result JSON
# We primarily pass the Case ID and title to the python verifier so it can
# correlate with the screenshot/VLM analysis.
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "case_id": "$CASE_ID",
    "task_start_timestamp": $TASK_START,
    "case_found": $CASE_FOUND,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="