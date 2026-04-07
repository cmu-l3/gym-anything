#!/bin/bash
# setup_task.sh — promotion_pipeline_setup
# Cleans all target entities in dependency order and ensures a known starting state.
set -e

source /workspace/scripts/task_utils.sh
chmod +x /workspace/tasks/promotion_pipeline_setup/export_result.sh 2>/dev/null || true

echo "=== promotion_pipeline_setup: Preparing environment ==="

# Wait for Artifactory to be ready (extended timeout for reliability)
wait_for_artifactory 300

# --- Idempotent cleanup (reverse dependency order) ---

# 1. Permissions first (reference repos + groups)
delete_permission_if_exists "deploy-perms"
delete_permission_if_exists "qa-perms"

# 2. Users (reference groups)
delete_user_if_exists "eng-sarah"

# 3. Groups
delete_group_if_exists "platform-engineers"
delete_group_if_exists "qa-team"

# 4. Virtual repo (references local + remote repos)
delete_repo_if_exists "medsecure-maven-all"

# 5. Local and remote repos
delete_repo_if_exists "medsecure-dev"
delete_repo_if_exists "medsecure-staging"
delete_repo_if_exists "medsecure-prod"
delete_repo_if_exists "maven-central-proxy"

# --- Ensure artifact is staged on Desktop ---
ARTIFACT_SRC="/home/ga/artifacts/commons-io/commons-io-2.15.1.jar"
ARTIFACT_DEST="/home/ga/Desktop/commons-io-2.15.1.jar"
MIN_ARTIFACT_SIZE=100000  # commons-io-2.15.1.jar is ~501 KB

needs_download() {
    local path="$1"
    [ ! -f "$path" ] && return 0
    local size
    size=$(stat -c%s "$path" 2>/dev/null || echo 0)
    [ "$size" -lt "$MIN_ARTIFACT_SIZE" ] && return 0
    return 1
}

# Re-download source if missing or corrupt
if needs_download "$ARTIFACT_SRC"; then
    echo "Downloading commons-io-2.15.1.jar from Maven Central..."
    mkdir -p "$(dirname "$ARTIFACT_SRC")"
    wget -q --timeout=60 -O "$ARTIFACT_SRC" \
        "https://repo1.maven.org/maven2/commons-io/commons-io/2.15.1/commons-io-2.15.1.jar" 2>/dev/null || true
fi

# Copy to Desktop if missing or corrupt
if needs_download "$ARTIFACT_DEST"; then
    if [ -f "$ARTIFACT_SRC" ] && ! needs_download "$ARTIFACT_SRC"; then
        cp "$ARTIFACT_SRC" "$ARTIFACT_DEST"
        echo "Staged artifact: $ARTIFACT_DEST ($(stat -c%s "$ARTIFACT_DEST") bytes)"
    else
        echo "WARNING: Could not obtain valid commons-io-2.15.1.jar. Upload task may fail."
    fi
fi

if [ -f "$ARTIFACT_DEST" ]; then
    chown ga:ga "$ARTIFACT_DEST" 2>/dev/null || true
fi

# --- Reset anonymous access to ENABLED (agent must disable it) ---
curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" \
    -X PATCH \
    -H "Content-Type: application/yaml" \
    -d 'security:
  anonAccessEnabled: true' \
    "${ARTIFACTORY_URL}/artifactory/api/system/configuration" > /dev/null 2>&1 || true
echo "Anonymous access reset to enabled."

# --- Reset SMTP mail server configuration (agent must configure it) ---
# Note: port must be an integer (null causes API error)
curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" \
    -X PATCH \
    -H "Content-Type: application/yaml" \
    -d 'mailServer:
  enabled: false
  host: ""
  port: 25
  from: ""
  subjectPrefix: ""
  username: ""
  password: ""
  ssl: false
  tls: false' \
    "${ARTIFACTORY_URL}/artifactory/api/system/configuration" > /dev/null 2>&1 || true
echo "SMTP mail server configuration reset."

# --- Record baselines ---
echo "$(date +%s)" > /tmp/task_start_ts
REPO_COUNT=$(get_repo_count)
echo "$REPO_COUNT" > /tmp/initial_repo_count
echo "Initial repo count: $REPO_COUNT"

# --- Navigate Firefox to the Repositories admin page ---
ensure_firefox_running
sleep 2
navigate_to "http://localhost:8082/ui/admin/repositories"
sleep 3
take_screenshot "/tmp/promotion_pipeline_setup_start.png"

echo "=== promotion_pipeline_setup: Setup complete ==="
exit 0
