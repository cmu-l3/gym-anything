#!/bin/bash
# setup_task.sh — tradex_platform_setup
# Removes all 6 target entities and ensures the upload artifact is present.
set -e

source /workspace/scripts/task_utils.sh
chmod +x /workspace/tasks/tradex_platform_setup/export_result.sh 2>/dev/null || true

echo "=== tradex_platform_setup: Preparing environment ==="

# Wait for Artifactory to be ready
wait_for_artifactory 120

# --- Idempotent cleanup ---
# Remove permission first (references repos + group)
delete_permission_if_exists "tradex-dev-perms"
delete_repo_if_exists "tradex-artifacts"
delete_repo_if_exists "tradex-maven-releases"
delete_group_if_exists "tradex-developers"

# Revoke any existing "TradeX CI/CD production token" access tokens
TOKENS_JSON=$(curl -s -u "admin:password" "http://localhost:8082/access/api/v1/tokens" 2>/dev/null || echo "")
if [ -n "$TOKENS_JSON" ]; then
    echo "$TOKENS_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for t in data.get('tokens', []):
        desc = t.get('description', '') or ''
        if 'TradeX CI/CD production token' in desc:
            print(t.get('token_id', ''))
except Exception:
    pass
" 2>/dev/null | while IFS= read -r tid; do
        if [ -n "$tid" ]; then
            curl -s -u "admin:password" -X DELETE \
                "http://localhost:8082/access/api/v1/tokens/$tid" > /dev/null 2>&1 || true
            echo "Revoked token: $tid"
        fi
    done
fi

# --- Ensure the upload artifact exists on the Desktop ---
# commons-io-2.15.1.jar should have been staged by setup_artifactory.sh
ARTIFACT_SRC="/home/ga/artifacts/commons-io/commons-io-2.15.1.jar"
ARTIFACT_DEST="/home/ga/Desktop/commons-io-2.15.1.jar"

if [ ! -f "$ARTIFACT_DEST" ]; then
    if [ -f "$ARTIFACT_SRC" ]; then
        cp "$ARTIFACT_SRC" "$ARTIFACT_DEST"
        echo "Copied artifact to Desktop: $ARTIFACT_DEST"
    else
        # Download from Maven Central as authoritative real source
        echo "Downloading commons-io-2.15.1.jar from Maven Central..."
        mkdir -p "$(dirname "$ARTIFACT_SRC")"
        wget -q --timeout=30 -O "$ARTIFACT_SRC" \
            "https://repo1.maven.org/maven2/commons-io/commons-io/2.15.1/commons-io-2.15.1.jar" 2>/dev/null || true
        if [ -f "$ARTIFACT_SRC" ] && [ "$(stat -c%s "$ARTIFACT_SRC" 2>/dev/null || echo 0)" -gt 50000 ]; then
            cp "$ARTIFACT_SRC" "$ARTIFACT_DEST"
            echo "Downloaded and staged artifact: $ARTIFACT_DEST"
        else
            echo "WARNING: Could not download commons-io-2.15.1.jar. Upload task may fail."
        fi
    fi
fi

# Ensure the artifact is owned by ga
if [ -f "$ARTIFACT_DEST" ]; then
    chown ga:ga "$ARTIFACT_DEST" 2>/dev/null || true
fi

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
take_screenshot "/tmp/tradex_platform_setup_start.png"

echo "=== tradex_platform_setup: Setup complete ==="
exit 0
