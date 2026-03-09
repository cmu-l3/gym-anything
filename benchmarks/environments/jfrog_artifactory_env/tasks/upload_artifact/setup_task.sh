#!/bin/bash
# Setup for: upload_artifact task
echo "=== Setting up upload_artifact task ==="

source /workspace/scripts/task_utils.sh

echo "Checking Artifactory connectivity..."
if ! wait_for_artifactory 60; then
    echo "ERROR: Artifactory is not accessible."
    exit 1
fi

# Remove any pre-existing commons-io upload from example-repo-local
echo "Clearing any existing commons-io artifacts from example-repo-local..."
curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" -X DELETE \
    "${ARTIFACTORY_URL}/artifactory/example-repo-local/commons-io-2.15.1.jar" \
    > /dev/null 2>&1 || true

# Verify the artifact file exists on the VM filesystem
ARTIFACT_FILE="/home/ga/artifacts/commons-io/commons-io-2.15.1.jar"
mkdir -p /home/ga/artifacts/commons-io

if [ ! -f "$ARTIFACT_FILE" ] || [ ! -s "$ARTIFACT_FILE" ]; then
    echo "Artifact file missing. Attempting download from Maven Central..."
    for MIRROR in \
        "https://repo1.maven.org/maven2/org/apache/commons/commons-io/2.15.1/commons-io-2.15.1.jar" \
        "https://search.maven.org/remotecontent?filepath=org/apache/commons/commons-io/2.15.1/commons-io-2.15.1.jar"; do
        if wget -q --timeout=60 "$MIRROR" -O "$ARTIFACT_FILE" 2>/dev/null && [ -s "$ARTIFACT_FILE" ]; then
            echo "Downloaded from: $MIRROR"
            break
        fi
    done
fi

if [ ! -f "$ARTIFACT_FILE" ] || [ ! -s "$ARTIFACT_FILE" ]; then
    echo "Download failed. Creating minimal valid JAR as placeholder..."
    python3 - << 'PYEOF'
import zipfile, io, os
buf = io.BytesIO()
with zipfile.ZipFile(buf, 'w', zipfile.ZIP_STORED) as z:
    z.writestr('META-INF/MANIFEST.MF',
               'Manifest-Version: 1.0\nImplementation-Title: Apache Commons IO\n'
               'Implementation-Version: 2.15.1\nCreated-By: gym_anything placeholder\n')
buf.seek(0)
os.makedirs('/home/ga/artifacts/commons-io', exist_ok=True)
with open('/home/ga/artifacts/commons-io/commons-io-2.15.1.jar', 'wb') as f:
    f.write(buf.read())
print("Created placeholder JAR: commons-io-2.15.1.jar")
PYEOF
fi

if [ -f "$ARTIFACT_FILE" ] && [ -s "$ARTIFACT_FILE" ]; then
    SIZE=$(stat -c%s "$ARTIFACT_FILE" 2>/dev/null || echo "unknown")
    echo "Artifact file ready: $ARTIFACT_FILE (${SIZE} bytes)"
else
    echo "ERROR: Could not prepare artifact file at $ARTIFACT_FILE"
fi

chown -R ga:ga /home/ga/artifacts/ 2>/dev/null || true

# Copy to Desktop for easy access via file picker
cp "$ARTIFACT_FILE" /home/ga/Desktop/commons-io-2.15.1.jar 2>/dev/null || true
chown ga:ga /home/ga/Desktop/commons-io-2.15.1.jar 2>/dev/null || true

INITIAL_COUNT=$(curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "${ARTIFACTORY_URL}/artifactory/api/search/quick?name=commons-io-2.15.1.jar&repos=example-repo-local" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('results', [])))" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_artifact_count

ensure_firefox_running "http://localhost:8082"
sleep 2
# Navigate to example-repo-local repository browser
navigate_to "http://localhost:8082/ui/repos/tree/General/example-repo-local"
sleep 4

take_screenshot /tmp/task_upload_artifact_initial.png

echo ""
echo "=== upload_artifact Task Setup Complete ==="
echo ""
echo "Task Instructions:"
echo "  1. Log in: admin / password at http://localhost:8082"
echo "  2. Navigate to Artifactory > Artifacts (or open example-repo-local in the repo browser)"
echo "  3. Use any method to deploy: Deploy button, drag-and-drop, or REST API"
echo "  4. Upload file: /home/ga/artifacts/commons-io/commons-io-2.15.1.jar"
echo "     (also available on the Desktop as commons-io-2.15.1.jar)"
echo "  5. Click Deploy"
echo ""
echo "The artifact file is also available on the Desktop: commons-io-2.15.1.jar"
echo ""
