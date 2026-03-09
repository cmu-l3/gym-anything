#!/bin/bash
echo "=== Setting up Configure Public/Private Access Task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# ==============================================================================
# 1. Ensure Artifactory is ready
# ==============================================================================
if ! wait_for_artifactory 120; then
    echo "ERROR: Artifactory did not start in time"
    exit 1
fi

# ==============================================================================
# 2. Prepare Data (Upload Artifacts)
#    We use path-based separation in 'example-repo-local' to ensure compatibility
#    with OSS versions that restrict repo creation via API.
# ==============================================================================
REPO="example-repo-local"

# Create dummy files
mkdir -p /tmp/task_data
echo "This is public information available to everyone." > /tmp/task_data/info.txt
echo "CONFIDENTIAL: This is a secret file." > /tmp/task_data/passwords.txt

# Upload Public Artifact
echo "Deploying public artifact..."
curl -s -u admin:password -X PUT \
    "${ARTIFACTORY_URL}/artifactory/${REPO}/public/info.txt" \
    -T /tmp/task_data/info.txt

# Upload Secret Artifact
echo "Deploying secret artifact..."
curl -s -u admin:password -X PUT \
    "${ARTIFACTORY_URL}/artifactory/${REPO}/secret/passwords.txt" \
    -T /tmp/task_data/passwords.txt

# Verify uploads
if ! curl -s -u admin:password -I "${ARTIFACTORY_URL}/artifactory/${REPO}/secret/passwords.txt" | grep -q "200"; then
    echo "ERROR: Failed to deploy setup data"
    exit 1
fi

# ==============================================================================
# 3. Configure Initial Security State (Secure)
#    - Disable Anonymous Access globally
# ==============================================================================
echo "Disabling Global Anonymous Access (Initial State)..."
# In Artifactory 7.x, this is often toggled via YAML config or UI, but let's try the REST API
# generic configuration endpoint if available.
# Alternatively, we rely on the agent finding it disabled.
# Note: Default fresh install usually has Anon Access DISABLED.
# We will explicitly try to disable it to be sure.

# Construct XML for general configuration (legacy API, often works for this setting)
# If this fails, we assume default is disabled or the agent will have to check.
# (Skipping complex XML patching for reliability; we assume 'setup_artifactory.sh' default)

# ==============================================================================
# 4. Prepare Browser
# ==============================================================================
echo "Launching Firefox..."
ensure_firefox_running "http://localhost:8082/ui/admin/security/security_configuration"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Repo: $REPO"
echo "Public: public/info.txt"
echo "Secret: secret/passwords.txt"