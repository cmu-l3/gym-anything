#!/bin/bash
echo "=== Exporting Provision Project Env Results ==="

source /workspace/scripts/task_utils.sh

ARTIFACTORY_URL="http://localhost:8082"
ADMIN_AUTH="admin:password"
USER_NAME="alpha-lead"
USER_PASS="Password123!"
REPO_KEY="alpha-local"

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Functional Testing (The most reliable verification for OSS)
#    We will try to act AS the new user to verify permissions.

# Create a test artifact
echo "Test content" > /tmp/test-artifact.txt

# TEST A: Authenticate and Upload (Should SUCCEED)
echo "Testing Upload Permission..."
UPLOAD_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "${USER_NAME}:${USER_PASS}" \
    -T /tmp/test-artifact.txt \
    "${ARTIFACTORY_URL}/artifactory/${REPO_KEY}/test-artifact.txt")

# TEST B: Delete (Should FAIL if permissions are correct)
echo "Testing Delete Permission (Should Fail)..."
DELETE_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X DELETE \
    -u "${USER_NAME}:${USER_PASS}" \
    "${ARTIFACTORY_URL}/artifactory/${REPO_KEY}/test-artifact.txt")

# TEST C: Verify Group Membership via Group API
# (In OSS, getting user details often fails, but getting Group details usually works)
echo "Checking Group Membership..."
GROUP_JSON=$(curl -s -u "${ADMIN_AUTH}" "${ARTIFACTORY_URL}/artifactory/api/security/groups/alpha-team")

# TEST D: Verify Permission Target via API
echo "Checking Permission Configuration..."
PERM_JSON=$(curl -s -u "${ADMIN_AUTH}" "${ARTIFACTORY_URL}/artifactory/api/security/permissions/alpha-access")

# TEST E: Verify Repository Existence via List
REPO_LIST=$(curl -s -u "${ADMIN_AUTH}" "${ARTIFACTORY_URL}/artifactory/api/repositories")

# 3. Clean up the test artifact (using admin, just in case user couldn't delete)
curl -s -u "${ADMIN_AUTH}" -X DELETE "${ARTIFACTORY_URL}/artifactory/${REPO_KEY}/test-artifact.txt" > /dev/null || true

# 4. Construct JSON Result
# We use jq (installed in env) or python to build the JSON safely
python3 -c "
import json
import sys

try:
    # Load raw API responses
    try:
        group_data = json.loads('''${GROUP_JSON}''')
    except:
        group_data = {}
    
    try:
        perm_data = json.loads('''${PERM_JSON}''')
    except:
        perm_data = {}
        
    try:
        repo_list = json.loads('''${REPO_LIST}''')
        repo_exists = any(r.get('key') == '${REPO_KEY}' for r in repo_list)
    except:
        repo_list = []
        repo_exists = False

    result = {
        'upload_http_code': int('${UPLOAD_CODE}'),
        'delete_http_code': int('${DELETE_CODE}'),
        'repo_exists': repo_exists,
        'group_exists': 'name' in group_data and group_data['name'] == 'alpha-team',
        'user_in_group': '${USER_NAME}' in group_data.get('userNames', []),
        'perm_exists': 'name' in perm_data and perm_data['name'] == 'alpha-access',
        'perm_data': perm_data,
        'timestamp': '$(date +%s)'
    }
    
    print(json.dumps(result, indent=2))

except Exception as e:
    print(json.dumps({'error': str(e)}))

" > /tmp/task_result.json

# 5. Permission fix for export
chmod 666 /tmp/task_result.json

echo "=== Export Complete ==="
cat /tmp/task_result.json