#!/bin/bash
# Export script for multi_arch_build_pipeline
# Verifies the registry state and image manifest

echo "=== Exporting Task Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check if Registry is running
REGISTRY_RUNNING="false"
if docker ps --format '{{.Ports}}' | grep -q "0.0.0.0:5000->5000/tcp"; then
    REGISTRY_RUNNING="true"
fi

# 2. Check if a custom builder exists (not just 'default')
# We look for a builder using the docker-container driver which is required for multi-arch
CUSTOM_BUILDER_EXISTS="false"
BUILDER_NAME=""
# Get list of builders and drivers
BUILDERS_INFO=$(docker buildx ls)

if echo "$BUILDERS_INFO" | grep -q "docker-container"; then
    CUSTOM_BUILDER_EXISTS="true"
    BUILDER_NAME=$(echo "$BUILDERS_INFO" | grep "docker-container" | awk '{print $1}' | sed 's/\*//' | head -1)
fi

# 3. Query Registry for Manifest
# We use curl to talk to the local registry
REPO_EXISTS="false"
MANIFEST_VALID="false"
PLATFORMS_FOUND=""
MANIFEST_CONTENT=""

if [ "$REGISTRY_RUNNING" = "true" ]; then
    # Check catalog
    CATALOG=$(curl -s http://localhost:5000/v2/_catalog 2>/dev/null || echo "")
    
    if echo "$CATALOG" | grep -q "edge-app"; then
        REPO_EXISTS="true"
        
        # Get Manifest
        # We need to accept the manifest list media type
        MANIFEST_RESPONSE=$(curl -s -H "Accept: application/vnd.docker.distribution.manifest.list.v2+json" \
                                   -H "Accept: application/vnd.oci.image.index.v1+json" \
                                   http://localhost:5000/v2/edge-app/manifests/latest)
        
        MANIFEST_CONTENT="$MANIFEST_RESPONSE"
        
        # Check for architectures in the manifest
        # We look for json structure "architecture": "amd64" and "architecture": "arm64"
        AMD64_FOUND=$(echo "$MANIFEST_RESPONSE" | grep -o '"architecture":\s*"amd64"' | wc -l)
        ARM64_FOUND=$(echo "$MANIFEST_RESPONSE" | grep -o '"architecture":\s*"arm64"' | wc -l)
        
        PLATFORMS_FOUND="amd64:$AMD64_FOUND,arm64:$ARM64_FOUND"
    fi
fi

# Capture logs from the builder container if it exists (for debugging/verification)
BUILDER_LOGS=""
if [ -n "$BUILDER_NAME" ]; then
    # The actual container name for a buildx builder is usually buildx_buildkit_<builder>0
    BUILDER_CONTAINER="buildx_buildkit_${BUILDER_NAME}0"
    if docker ps -a --format '{{.Names}}' | grep -q "$BUILDER_CONTAINER"; then
        BUILDER_LOGS=$(docker logs --tail 20 "$BUILDER_CONTAINER" 2>/dev/null | base64 -w 0)
    fi
fi

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "registry_running": $REGISTRY_RUNNING,
    "custom_builder_exists": $CUSTOM_BUILDER_EXISTS,
    "builder_name": "$BUILDER_NAME",
    "repo_exists": $REPO_EXISTS,
    "manifest_content": $(echo "$MANIFEST_CONTENT" | jq -R . 2>/dev/null || echo "\"\""),
    "platforms_found": "$PLATFORMS_FOUND",
    "timestamp": $(date +%s)
}
EOF

# Save result safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="