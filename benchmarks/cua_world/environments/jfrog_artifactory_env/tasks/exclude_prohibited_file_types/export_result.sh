#!/bin/bash
echo "=== Exporting exclude_prohibited_file_types results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Prepare test files
echo "Valid content" > /tmp/test_valid.txt
echo "Malicious binary content" > /tmp/test_malware.exe
echo "Library binary content" > /tmp/test_lib.dll

REPO="example-repo-local"
BASE_URL="${ARTIFACTORY_URL}/artifactory/${REPO}"

# Function to upload file and return HTTP code
upload_file() {
    local file_path=$1
    local dest_path=$2
    local filename=$(basename "$file_path")
    
    # Use -T to upload file
    curl -s -o /dev/null -w "%{http_code}" \
        -u "${ADMIN_USER}:${ADMIN_PASS}" \
        -T "$file_path" \
        "${BASE_URL}/${dest_path}/${filename}"
}

echo "Running functional tests..."

# Test 1: Positive Control (Should SUCCEED)
# Upload a text file. If this fails, the agent broke the repo or permissions.
CODE_TXT=$(upload_file "/tmp/test_valid.txt" "verification/test_valid.txt")
echo "Upload .txt result: $CODE_TXT"

# Test 2: Negative Control A (Should FAIL)
# Upload .exe file.
CODE_EXE=$(upload_file "/tmp/test_malware.exe" "verification/test_malware.exe")
echo "Upload .exe result: $CODE_EXE"

# Test 3: Negative Control B (Should FAIL)
# Upload .dll file.
CODE_DLL=$(upload_file "/tmp/test_lib.dll" "verification/test_lib.dll")
echo "Upload .dll result: $CODE_DLL"

# Retrieve Repository Configuration
# We fetch the configuration to inspect the patterns directly
REPO_CONFIG_JSON=$(art_api GET "/api/repositories/${REPO}")

# Save results to JSON
# We use Python to construct the JSON carefully to handle quoting/escaping
python3 -c "
import json
import os

result = {
    'http_txt': '$CODE_TXT',
    'http_exe': '$CODE_EXE',
    'http_dll': '$CODE_DLL',
    'repo_config': json.loads('''$REPO_CONFIG_JSON''' or '{}'),
    'timestamp': '$(date -Iseconds)'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Clean up test artifacts from Artifactory (if upload succeeded)
# We delete the 'verification' folder we created
art_api DELETE "/${REPO}/verification" > /dev/null 2>&1 || true

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="