#!/bin/bash
set -e
echo "=== Setting up Retrieve Archive Entry task ==="

source /workspace/scripts/task_utils.sh

# 1. Wait for Artifactory
if ! wait_for_artifactory 120; then
    echo "ERROR: Artifactory not ready"
    exit 1
fi

# 2. Generate dynamic secret content
# This ensures the agent must actually look at the file, not guess
DB_HOST="db-prod-$(shuf -i 1000-9999 -n 1).internal"
SECRET_KEY="$(date +%s | sha256sum | head -c 16)"
CONFIG_CONTENT="db.url=jdbc:mysql://${DB_HOST}:3306/main
feature.new_ui=true
security.salt=${SECRET_KEY}
# This file is critical for production connectivity"

echo "Generated secret content:"
echo "$CONFIG_CONTENT"

# Save expected content to a hidden location for verification
echo "$CONFIG_CONTENT" > /tmp/expected_config.txt
chmod 644 /tmp/expected_config.txt

# 3. Create the zip artifact locally using Python (to avoid missing 'zip' utility)
WORK_DIR="/tmp/artifact_prep"
mkdir -p "$WORK_DIR"

python3 -c "
import zipfile
import os

content = '''$CONFIG_CONTENT'''
work_dir = '$WORK_DIR'
zip_path = os.path.join(work_dir, 'app-bundle-v2.0.zip')

with zipfile.ZipFile(zip_path, 'w') as z:
    z.writestr('config.properties', content)
    z.writestr('index.html', '<html><body><h1>App v2.0</h1></body></html>')
    z.writestr('lib/dummy.jar', 'PK0000') # Dummy binary content
"

ARTIFACT_PATH="$WORK_DIR/app-bundle-v2.0.zip"

# 4. Upload to Artifactory
REPO="example-repo-local"
TARGET_PATH="com/acme/app/2.0/app-bundle-v2.0.zip"

echo "Uploading artifact to $REPO/$TARGET_PATH..."
curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" \
    -X PUT \
    -T "$ARTIFACT_PATH" \
    "${ARTIFACTORY_URL}/artifactory/${REPO}/${TARGET_PATH}" > /dev/null

# 5. Cleanup
rm -rf "$WORK_DIR"
rm -f /home/ga/recovered_config.properties

# 6. Record start time
date +%s > /tmp/task_start_time.txt

# 7. Prepare browser
ensure_firefox_running "${ARTIFACTORY_URL}/ui/packages"
sleep 5

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="