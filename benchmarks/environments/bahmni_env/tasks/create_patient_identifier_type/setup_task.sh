#!/bin/bash
set -e

echo "=== Setting up create_patient_identifier_type task ==="

# Source shared Bahmni task utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming detection)
date +%s > /tmp/task_start_time.txt

# Ensure Bahmni is running and accessible
log "Checking Bahmni availability..."
wait_for_bahmni 300

# Authentication details
AUTH="-u ${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}"
API_URL="${OPENMRS_API_URL}"

# 1. Clean up: Check if 'National Health ID' already exists and retire/delete it
log "Checking for existing 'National Health ID' identifier type..."

# Fetch all identifier types
EXISTING_ID=$(curl -sk $AUTH "${API_URL}/patientidentifiertype?v=default&limit=100" | \
  python3 -c "import sys, json; 
data = json.load(sys.stdin); 
results = data.get('results', []); 
match = next((r for r in results if 'national health' in r.get('display', '').lower()), None);
print(match['uuid'] if match else '')")

if [ -n "$EXISTING_ID" ]; then
  log "Found existing identifier type (UUID: $EXISTING_ID). Purging it for clean state..."
  # Purge (hard delete) to allow creating a new one with the same name
  curl -sk -X DELETE $AUTH "${API_URL}/patientidentifiertype/${EXISTING_ID}?purge=true" || true
  sleep 2
else
  log "No existing identifier type found. Clean state verified."
fi

# 2. Record initial count of patient identifier types (for anti-gaming)
INITIAL_COUNT=$(curl -sk $AUTH "${API_URL}/patientidentifiertype?v=default&limit=100" | \
  python3 -c "import sys, json; print(len(json.load(sys.stdin).get('results', [])))" || echo "0")

echo "$INITIAL_COUNT" > /tmp/initial_id_type_count.txt
log "Initial patient identifier type count: $INITIAL_COUNT"

# 3. Start browser at Bahmni home page
log "Starting browser..."
start_browser "${BAHMNI_BASE_URL}/bahmni/home" 4

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

log "=== Task setup complete ==="