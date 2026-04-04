#!/bin/bash
set -e
echo "=== Setting up deploy_maven_multi_artifact task ==="

source /workspace/scripts/task_utils.sh

# 1. Wait for Artifactory to be ready
echo "Checking Artifactory connectivity..."
if ! wait_for_artifactory 120; then
    echo "ERROR: Artifactory is not accessible. Cannot proceed."
    exit 1
fi

# 2. Ensure Example Repo Exists (it should be default, but good to check)
if ! repo_exists "example-repo-local"; then
    echo "WARNING: example-repo-local does not exist. The task might fail if the agent cannot deploy to it."
    # In a real scenario we might create it, but for this task we assume it exists or agent fails.
fi

# 3. Prepare Source Files on Desktop
echo "Preparing source files..."
ARTIFACTS_DIR="/home/ga/artifacts"
DESKTOP_DIR="/home/ga/Desktop"

# Ensure POMs are copied (JARs are usually copied by env setup, but we force copy all to be safe)
cp -f "${ARTIFACTS_DIR}/commons-lang3/commons-lang3-3.14.0.jar" "${DESKTOP_DIR}/" 2>/dev/null || true
cp -f "${ARTIFACTS_DIR}/commons-lang3/commons-lang3-3.14.0.pom" "${DESKTOP_DIR}/" 2>/dev/null || true
cp -f "${ARTIFACTS_DIR}/commons-io/commons-io-2.15.1.jar" "${DESKTOP_DIR}/" 2>/dev/null || true
cp -f "${ARTIFACTS_DIR}/commons-io/commons-io-2.15.1.pom" "${DESKTOP_DIR}/" 2>/dev/null || true

chown ga:ga "${DESKTOP_DIR}"/* 2>/dev/null || true

# 4. Calculate Source Checksums for Verification
# We calculate these now to compare later
echo "Calculating source checksums..."
sha256sum "${DESKTOP_DIR}/commons-lang3-3.14.0.jar" | awk '{print $1}' > /tmp/checksum_lang3_jar.txt
sha256sum "${DESKTOP_DIR}/commons-lang3-3.14.0.pom" | awk '{print $1}' > /tmp/checksum_lang3_pom.txt
sha256sum "${DESKTOP_DIR}/commons-io-2.15.1.jar"    | awk '{print $1}' > /tmp/checksum_io_jar.txt
sha256sum "${DESKTOP_DIR}/commons-io-2.15.1.pom"    | awk '{print $1}' > /tmp/checksum_io_pom.txt

# 5. Clean Destination Paths (Anti-gaming)
# Delete specific paths if they already exist to ensure agent actually deploys them
echo "Cleaning target paths..."
# Note: In Artifactory, deleting a folder deletes contents.
# We delete the version folders to be clean.
art_api DELETE "/example-repo-local/org/apache/commons/commons-lang3/3.14.0" > /dev/null 2>&1 || true
art_api DELETE "/example-repo-local/commons-io/commons-io/2.15.1" > /dev/null 2>&1 || true

# 6. Record Start Time
date +%s > /tmp/task_start_time.txt

# 7. Start Application
echo "Starting Firefox..."
ensure_firefox_running "http://localhost:8082"

# Wait for load
sleep 5

# 8. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="