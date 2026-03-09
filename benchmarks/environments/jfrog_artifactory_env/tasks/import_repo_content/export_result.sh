#!/bin/bash
echo "=== Exporting import_repo_content results ==="

source /workspace/scripts/task_utils.sh

# Capture final state screenshot
take_screenshot /tmp/task_final.png

# Details for verification
TARGET_REPO="example-repo-local"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Define expected artifacts
declare -a EXPECTED_ARTIFACTS=(
    "org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.jar"
    "org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.pom"
    "org/apache/commons/commons-io/2.15.1/commons-io-2.15.1.jar"
    "org/apache/commons/commons-io/2.15.1/commons-io-2.15.1.pom"
)

# JSON Construction using python for safety
python3 -c "
import json
import os
import requests
import time

repo = '$TARGET_REPO'
base_url = 'http://localhost:8082/artifactory/api/storage/' + repo
auth = ('admin', 'password')
task_start = $TASK_START_TIME

results = {
    'artifacts': {},
    'repo_status': {},
    'task_timestamp': task_start
}

artifacts = [
    'org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.jar',
    'org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.pom',
    'org/apache/commons/commons-io/2.15.1/commons-io-2.15.1.jar',
    'org/apache/commons/commons-io/2.15.1/commons-io-2.15.1.pom'
]

valid_count = 0

for art in artifacts:
    url = base_url + '/' + art
    try:
        r = requests.get(url, auth=auth, timeout=5)
        exists = (r.status_code == 200)
        
        created_time = 0
        created_by = ''
        size = 0
        
        if exists:
            data = r.json()
            # Artifactory returns ISO timestamps, e.g., 2024-05-20T10:00:00.000Z
            iso_time = data.get('created', '')
            try:
                # Simple parsing or just string check
                # Note: 'created' is when it was uploaded to Artifactory
                # 'lastModified' is usually preserved from file
                pass
            except:
                pass
                
            created_by = data.get('createdBy', '')
            size = data.get('size', 0)
            
            # Since we can't easily parse ISO in minimal python without installing libs,
            # we rely on the verifier to check timestamps if needed, or check 'createdBy'.
            # Ideally imports show createdBy the user who imported.
            
            if size > 100: # Valid file check
                valid_count += 1
                
        results['artifacts'][art] = {
            'exists': exists,
            'status_code': r.status_code,
            'size': size,
            'createdBy': created_by
        }
    except Exception as e:
        results['artifacts'][art] = {'exists': False, 'error': str(e)}

# Check Repo Storage Info
try:
    r = requests.get('http://localhost:8082/artifactory/api/storageinfo', auth=auth, timeout=5)
    if r.status_code == 200:
        si = r.json()
        # Navigate complex json structure of storageinfo
        # usually repositoriesSummaryList -> repoKey
        summary = si.get('repositoriesSummaryList', [])
        target_summary = next((r for r in summary if r.get('repoKey') == repo), None)
        if target_summary:
            results['repo_status'] = target_summary
except:
    pass

results['valid_artifact_count'] = valid_count

# Write to temp file
with open('/tmp/export_data.json', 'w') as f:
    json.dump(results, f, indent=2)
"

# Handle permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/export_data.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json