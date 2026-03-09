#!/bin/bash
set -e
echo "=== Setting up create_concept_class task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Bahmni/OpenMRS is running
wait_for_bahmni 600

echo "Checking for existing 'PRAPARE Assessment' concept class..."

# Check if the class already exists via REST API
# OpenMRS Concept Class API: /ws/rest/v1/conceptclass
EXISTING_CLASS=$(curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
  "${OPENMRS_API_URL}/conceptclass?q=PRAPARE&v=default" 2>/dev/null)

# Parse UUID if exists
CLASS_UUID=$(echo "$EXISTING_CLASS" | python3 -c "import sys, json; \
data = json.load(sys.stdin); \
results = data.get('results', []); \
matches = [r for r in results if 'PRAPARE' in r.get('display', '').upper()]; \
print(matches[0]['uuid'] if matches else '')" 2>/dev/null || true)

if [ -n "$CLASS_UUID" ]; then
    echo "Found existing class with UUID: $CLASS_UUID. Purging..."
    # Purge the class to ensure a clean state
    curl -sk -X DELETE \
      -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
      "${OPENMRS_API_URL}/conceptclass/${CLASS_UUID}?purge=true" 2>/dev/null
    
    echo "Existing class purged."
    sleep 2
else
    echo "No existing class found. Clean state verified."
fi

# Start browser at Bahmni Home to force navigation
start_browser "${BAHMNI_LOGIN_URL}"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="