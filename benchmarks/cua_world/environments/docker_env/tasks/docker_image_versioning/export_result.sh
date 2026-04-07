#!/bin/bash
echo "=== Exporting Docker Image Versioning Results ==="

# Don't use set -e to ensure we capture partial failures
source /workspace/scripts/task_utils.sh 2>/dev/null || true

PROJECT_DIR="/home/ga/projects/acme-payment-service"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
IMAGE_TAG="acme-payment:latest"

take_screenshot /tmp/task_final.png

# Switch to project dir
cd "$PROJECT_DIR" || exit 1

# --- DYNAMIC VERIFICATION STEP (Anti-Gaming) ---
# We must verify the build pipeline works for ANY commit, not just the one the agent saw.
# We will create a new commit, run the agent's build script, and check the result.

echo "Creating audit commit..."
git config user.email "verifier@acme.corp"
git config user.name "Verifier"
git commit --allow-empty -m "Verifier Audit Commit $(date +%s)" > /dev/null
EXPECTED_SHA=$(git rev-parse HEAD)
EXPECTED_SHORT_SHA=$(git rev-parse --short HEAD)
EXPECTED_BRANCH=$(git rev-parse --abbrev-ref HEAD)

echo "Running agent's build.sh with new commit $EXPECTED_SHORT_SHA..."
# Run build.sh as ga user to match permission context
if [ -f "./build.sh" ]; then
    chown ga:ga . -R
    su - ga -c "cd $PROJECT_DIR && ./build.sh" > /tmp/verifier_build.log 2>&1
    BUILD_EXIT_CODE=$?
else
    echo "build.sh not found!"
    BUILD_EXIT_CODE=1
fi

# --- INSPECT RESULTING IMAGE ---
IMAGE_EXISTS="false"
ENV_REVISION=""
ENV_BRANCH=""
LABEL_REVISION=""
LABEL_CREATED=""
LABEL_SOURCE=""

if docker inspect "$IMAGE_TAG" > /dev/null 2>&1; then
    IMAGE_EXISTS="true"
    
    # Extract Env vars
    ENV_REVISION=$(docker inspect "$IMAGE_TAG" --format '{{range .Config.Env}}{{if (call .startswith "APP_REVISION=") }}{{.}}{{end}}{{end}}' | cut -d= -f2)
    ENV_BRANCH=$(docker inspect "$IMAGE_TAG" --format '{{range .Config.Env}}{{if (call .startswith "APP_BRANCH=") }}{{.}}{{end}}{{end}}' | cut -d= -f2)
    
    # Extract Labels
    LABEL_REVISION=$(docker inspect "$IMAGE_TAG" --format '{{index .Config.Labels "org.opencontainers.image.revision"}}')
    LABEL_CREATED=$(docker inspect "$IMAGE_TAG" --format '{{index .Config.Labels "org.opencontainers.image.created"}}')
    LABEL_SOURCE=$(docker inspect "$IMAGE_TAG" --format '{{index .Config.Labels "org.opencontainers.image.source"}}')
fi

# --- RUNTIME CHECK ---
# Does the container actually run and serve the data?
APP_STARTS="false"
APP_RESPONSE_SHA=""
APP_RESPONSE_BRANCH=""

if [ "$IMAGE_EXISTS" = "true" ]; then
    # Stop any existing container
    docker rm -f acme-test 2>/dev/null || true
    
    # Run detached
    docker run -d --name acme-test -p 5099:5000 "$IMAGE_TAG" > /dev/null
    
    # Wait for startup
    sleep 5
    
    # Check if running
    if [ "$(docker inspect -f '{{.State.Running}}' acme-test 2>/dev/null)" = "true" ]; then
        APP_STARTS="true"
        
        # Query endpoint
        RESPONSE=$(curl -s http://localhost:5099/version || echo "")
        
        # Extract JSON fields (simple grep/python parsing since jq might be missing)
        APP_RESPONSE_SHA=$(echo "$RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('revision', ''))" 2>/dev/null)
        APP_RESPONSE_BRANCH=$(echo "$RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('branch', ''))" 2>/dev/null)
    fi
    
    # Cleanup
    docker rm -f acme-test > /dev/null 2>&1
fi

# Create Result JSON
cat > /tmp/task_result.json <<EOF
{
    "task_start": $TASK_START,
    "build_exit_code": $BUILD_EXIT_CODE,
    "image_exists": $IMAGE_EXISTS,
    "expected_sha": "$EXPECTED_SHA",
    "expected_branch": "$EXPECTED_BRANCH",
    "env_revision": "$ENV_REVISION",
    "env_branch": "$ENV_BRANCH",
    "label_revision": "$LABEL_REVISION",
    "label_created": "$LABEL_CREATED",
    "label_source": "$LABEL_SOURCE",
    "app_starts": $APP_STARTS,
    "app_response_sha": "$APP_RESPONSE_SHA",
    "app_response_branch": "$APP_RESPONSE_BRANCH",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Secure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result:"
cat /tmp/task_result.json