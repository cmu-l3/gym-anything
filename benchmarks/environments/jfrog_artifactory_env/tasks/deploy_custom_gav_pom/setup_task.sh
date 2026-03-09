#!/bin/bash
set -e
echo "=== Setting up deploy_custom_gav_pom task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Create the dummy artifact file on Desktop
SOURCE_FILE="/home/ga/Desktop/acme_db_driver_v2.5.jar"
echo "Creating dummy driver file at $SOURCE_FILE..."

# Create a valid zip/jar file structure so Artifactory accepts it
python3 -c "
import zipfile
with zipfile.ZipFile('$SOURCE_FILE', 'w') as z:
    z.writestr('META-INF/MANIFEST.MF', 'Manifest-Version: 1.0\nCreated-By: Acme Corp\n')
    z.writestr('com/acme/Driver.class', 'DUMMY_BYTECODE')
"

# Set ownership
chown ga:ga "$SOURCE_FILE"

# Calculate source checksum for verification later
sha256sum "$SOURCE_FILE" | cut -d' ' -f1 > /tmp/source_checksum.txt
echo "Source SHA256: $(cat /tmp/source_checksum.txt)"

# 2. Ensure Artifactory is ready
echo "Waiting for Artifactory..."
if ! wait_for_artifactory 120; then
    echo "ERROR: Artifactory did not start."
    exit 1
fi

# 3. Ensure example-repo-local exists
# (It's default, but if deleted by previous task, recreate it)
if ! repo_exists "example-repo-local"; then
    echo "Recreating example-repo-local..."
    # Create via API (simplest config)
    art_api PUT "/api/repositories/example-repo-local" \
        '{"rclass":"local","packageType":"maven"}'
fi

# 4. Clean up any previous attempts at the target path
# We want to ensure the agent actually creates it NOW.
TARGET_PATH="com/acme/db/driver/2.5.0"
echo "Cleaning up potential existing artifacts at $TARGET_PATH..."
art_api DELETE "/example-repo-local/$TARGET_PATH" >/dev/null 2>&1 || true

# 5. Start Firefox and navigate to login
echo "Starting Firefox..."
ensure_firefox_running "http://localhost:8082"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="