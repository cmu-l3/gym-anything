#!/bin/bash
# Export script for compose_profiles_multi_team task

echo "=== Exporting compose_profiles_multi_team results ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/ecommerce-platform"
COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check file modification
FILE_MODIFIED="false"
FILE_MTIME=0
if [ -f "$COMPOSE_FILE" ]; then
    FILE_MTIME=$(stat -c %Y "$COMPOSE_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# 2. Check if YAML is valid and parse profiles
# We use `docker compose config` to see what services are included for each profile
# This is the most robust way to verify configuration

get_services_for_profile() {
    local profile="$1"
    # Run config with specific profile and list services
    # --profile "" simulates no profile (only base services should show)
    if [ -z "$profile" ]; then
        docker compose -f "$COMPOSE_FILE" config --services 2>/dev/null | sort | tr '\n' ',' | sed 's/,$//'
    else
        docker compose -f "$COMPOSE_FILE" --profile "$profile" config --services 2>/dev/null | sort | tr '\n' ',' | sed 's/,$//'
    fi
}

echo "Analyzing profiles..."
SERVICES_NO_PROFILE=$(get_services_for_profile "")
SERVICES_FRONTEND=$(get_services_for_profile "frontend")
SERVICES_BACKEND=$(get_services_for_profile "backend")
SERVICES_DEBUG=$(get_services_for_profile "debug")
SERVICES_FULL=$(get_services_for_profile "full")

# 3. Check for specific anti-gaming requirement: 
# "postgres" and "redis" must NOT have a "profiles" key in the raw YAML.
# If they do (e.g. profiles: ["frontend", "backend"...]), it technically works but violates
# the "Base services (no profile)" requirement.
BASE_SERVICES_HAVE_PROFILES="false"

# Use python to parse YAML for this specific check since grep is brittle
cat > /tmp/check_yaml.py << 'PYEOF'
import yaml
import sys

try:
    with open(sys.argv[1], 'r') as f:
        data = yaml.safe_load(f)
    
    services = data.get('services', {})
    bad = False
    details = []
    
    for svc in ['postgres', 'redis']:
        if 'profiles' in services.get(svc, {}):
            bad = True
            details.append(f"{svc} has profiles key")
            
    print("true" if bad else "false")
except Exception as e:
    print("error")
PYEOF

if [ -f "$COMPOSE_FILE" ]; then
    # We need pyyaml, but we can't assume it's installed in the slim environment
    # Fallback to grep if python fails or pyyaml missing
    if python3 -c "import yaml" 2>/dev/null; then
        BASE_SERVICES_HAVE_PROFILES=$(python3 /tmp/check_yaml.py "$COMPOSE_FILE")
    else
        # Fallback: grep for 'profiles' indented under postgres/redis
        # This is heuristics-based and imperfect but better than nothing
        # We look for "postgres:" ... "profiles:" in that block
        # Hard to do reliably with grep, so we'll skip this check if pyyaml is missing
        # and rely on the "SERVICES_NO_PROFILE" check above (which must return only postgres,redis)
        echo "PyYAML not found, skipping deep introspection of base services"
        BASE_SERVICES_HAVE_PROFILES="unknown"
    fi
fi

# 4. Check what containers are currently running
# Agent should have started backend (4 services) then stopped them
# We record current state just in case
CURRENT_RUNNING=$(docker compose -f "$COMPOSE_FILE" ps --format '{{.Service}}' 2>/dev/null | sort | tr '\n' ',' | sed 's/,$//')

# 5. Read raw content for diffing in verifier
RAW_CONTENT=""
if [ -f "$COMPOSE_FILE" ]; then
    # Read file, escape double quotes and backslashes
    RAW_CONTENT=$(cat "$COMPOSE_FILE" | base64 -w 0)
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $([ -f "$COMPOSE_FILE" ] && echo "true" || echo "false"),
    "file_modified": $FILE_MODIFIED,
    "services_no_profile": "$SERVICES_NO_PROFILE",
    "services_frontend": "$SERVICES_FRONTEND",
    "services_backend": "$SERVICES_BACKEND",
    "services_debug": "$SERVICES_DEBUG",
    "services_full": "$SERVICES_FULL",
    "base_services_have_profiles_key": "$BASE_SERVICES_HAVE_PROFILES",
    "current_running_services": "$CURRENT_RUNNING",
    "raw_content_base64": "$RAW_CONTENT",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="