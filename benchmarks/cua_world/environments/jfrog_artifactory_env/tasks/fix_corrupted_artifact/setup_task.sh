#!/bin/bash
set -e
echo "=== Setting up Fix Corrupted Artifact Task ==="

source /workspace/scripts/task_utils.sh

# 1. Wait for Artifactory to be ready
echo "Waiting for Artifactory..."
wait_for_artifactory 120 || exit 1

# 2. Ensure repository exists
if ! repo_exists "example-repo-local"; then
    echo "Creating 'example-repo-local'..."
    # Create generic local repo if missing (should be there by default)
    art_api PUT "/api/repositories/example-repo-local" \
        '{"rclass":"local","packageType":"generic"}'
fi

# 3. Create and upload CORRUPTED artifact
echo "Creating corrupted artifact..."
CORRUPTED_FILE="/tmp/corrupted.jar"
echo "This is not a valid JAR file. It is corrupted text data." > "$CORRUPTED_FILE"

ARTIFACT_PATH="example-repo-local/org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.jar"
UPLOAD_URL="${ARTIFACTORY_URL}/artifactory/${ARTIFACT_PATH}"

echo "Uploading corrupted artifact to $UPLOAD_URL..."
curl -u "${ADMIN_USER}:${ADMIN_PASS}" -T "$CORRUPTED_FILE" "$UPLOAD_URL"

# Record the checksum of the corrupted file for anti-gaming verification
BAD_SHA256=$(sha256sum "$CORRUPTED_FILE" | cut -d' ' -f1)
echo "$BAD_SHA256" > /tmp/corrupted_sha256.txt
echo "Corrupted SHA256: $BAD_SHA256"

# 4. Prepare the VALID file on Desktop
echo "Preparing valid file on Desktop..."
# The environment setup script downloads real artifacts to /home/ga/artifacts
SOURCE_JAR="/home/ga/artifacts/commons-lang3/commons-lang3-3.14.0.jar"
DEST_JAR="/home/ga/Desktop/commons-lang3-3.14.0.jar"

if [ -f "$SOURCE_JAR" ]; then
    cp "$SOURCE_JAR" "$DEST_JAR"
else
    # Fallback if environment setup failed (should not happen, but safe)
    echo "Downloading valid JAR..."
    wget -q -O "$DEST_JAR" "https://repo1.maven.org/maven2/org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.jar"
fi
chmod 644 "$DEST_JAR"
chown ga:ga "$DEST_JAR"

# Record valid SHA256
VALID_SHA256=$(sha256sum "$DEST_JAR" | cut -d' ' -f1)
echo "$VALID_SHA256" > /tmp/valid_sha256.txt
echo "Valid SHA256: $VALID_SHA256"

# 5. Start Firefox and navigate to Artifacts browser
echo "Starting Firefox..."
ensure_firefox_running "${ARTIFACTORY_URL}/ui/packages"
sleep 5

# Navigate specifically to the tree view if possible, or just the main page
navigate_to "${ARTIFACTORY_URL}/ui/repos/tree/General/example-repo-local/org/apache/commons/commons-lang3/3.14.0"
sleep 5

# 6. Capture initial state
take_screenshot /tmp/task_initial.png

# Record start time
date +%s > /tmp/task_start_time.txt

echo "=== Setup Complete ==="