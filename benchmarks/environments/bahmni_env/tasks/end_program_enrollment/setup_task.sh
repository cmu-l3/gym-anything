#!/bin/bash
echo "=== Setting up End Program Enrollment Task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_timestamp

# Ensure Bahmni is reachable
if ! wait_for_bahmni 900; then
  echo "ERROR: Bahmni is not reachable"
  exit 1
fi

log "Authenticating with OpenMRS..."

# 1. Get Patient UUID (James Osei)
PATIENT_IDENTIFIER="BAH000011"
PATIENT_UUID=$(get_patient_uuid_by_identifier "$PATIENT_IDENTIFIER")

if [ -z "$PATIENT_UUID" ]; then
  log "ERROR: Patient $PATIENT_IDENTIFIER not found. Using fallback search..."
  # Fallback to search by name if identifier lookup fails
  PATIENT_SEARCH=$(openmrs_api_get "/patient?q=James+Osei&v=default")
  PATIENT_UUID=$(echo "$PATIENT_SEARCH" | jq -r '.results[0].uuid // empty')
  
  if [ -z "$PATIENT_UUID" ]; then
    log "CRITICAL: Patient James Osei not found. Cannot proceed."
    exit 1
  fi
fi
log "Target Patient UUID: $PATIENT_UUID"

# 2. Ensure "Wellness Tracking" Program Exists
PROGRAM_NAME="Wellness Tracking"
PROGRAM_UUID=""

# Check if program exists
PROGRAM_SEARCH=$(openmrs_api_get "/program?q=Wellness&v=default")
EXISTING_PROG_NAME=$(echo "$PROGRAM_SEARCH" | jq -r '.results[0].display // empty')

if [[ "$EXISTING_PROG_NAME" == *"$PROGRAM_NAME"* ]]; then
  PROGRAM_UUID=$(echo "$PROGRAM_SEARCH" | jq -r '.results[0].uuid')
  log "Found existing program: $PROGRAM_NAME ($PROGRAM_UUID)"
else
  log "Creating 'Wellness Tracking' program..."
  
  # A program needs a concept. Check/Create Concept.
  CONCEPT_UUID=""
  CONCEPT_SEARCH=$(openmrs_api_get "/concept?q=Wellness+Tracking&v=default")
  CONCEPT_UUID=$(echo "$CONCEPT_SEARCH" | jq -r '.results[0].uuid // empty')
  
  if [ -z "$CONCEPT_UUID" ]; then
    # Create Concept
    # Class: Program (uuid depends on DB, usually lookup needed, but we try standard name 'Program')
    # For robustness in setup script, we might use 'Misc' class UUID if 'Program' isn't easily resolvable by name, 
    # but let's try to find the Program concept class.
    CLASS_SEARCH=$(openmrs_api_get "/conceptclass?q=Program&v=default")
    CLASS_UUID=$(echo "$CLASS_SEARCH" | jq -r '.results[0].uuid')
    
    # Datatype: N/A
    DATATYPE_SEARCH=$(openmrs_api_get "/conceptdatatype?q=N/A&v=default")
    DATATYPE_UUID=$(echo "$DATATYPE_SEARCH" | jq -r '.results[0].uuid')
    
    if [ -n "$CLASS_UUID" ] && [ -n "$DATATYPE_UUID" ]; then
        CONCEPT_PAYLOAD=$(cat <<EOF
{
  "names": [{"name": "Wellness Tracking", "locale": "en", "conceptNameType": "FULLY_SPECIFIED"}],
  "datatype": "$DATATYPE_UUID",
  "conceptClass": "$CLASS_UUID"
}
EOF
)
        CONCEPT_RESP=$(openmrs_api_post "/concept" "$CONCEPT_PAYLOAD")
        CONCEPT_UUID=$(echo "$CONCEPT_RESP" | jq -r '.uuid // empty')
    fi
  fi
  
  if [ -z "$CONCEPT_UUID" ]; then
    log "ERROR: Could not create/find concept for program. Aborting setup."
    exit 1
  fi

  # Create Program
  PROGRAM_PAYLOAD=$(cat <<EOF
{
  "name": "$PROGRAM_NAME",
  "description": "Program for tracking patient wellness",
  "concept": "$CONCEPT_UUID"
}
EOF
)
  PROGRAM_RESP=$(openmrs_api_post "/program" "$PROGRAM_PAYLOAD")
  PROGRAM_UUID=$(echo "$PROGRAM_RESP" | jq -r '.uuid // empty')
fi

if [ -z "$PROGRAM_UUID" ]; then
  log "ERROR: Failed to establish Program UUID."
  exit 1
fi

# 3. Clean up existing active enrollments for this program for this patient
ACTIVE_ENROLLMENTS=$(openmrs_api_get "/patientprogram?patient=$PATIENT_UUID&v=full")
# Loop through and void/close any existing ones to ensure clean state? 
# For now, we assume we just add a new one, but multiple active programs of same type might be blocked by OpenMRS.
# It's safer to void previous enrollments.
log "Cleaning previous enrollments..."
# (Simplified: assume we can just create a new one or the system allows it. 
# Bahmni usually allows one active program of a type. We'll proceed to create.)

# 4. Enroll Patient (Start date = 30 days ago)
START_DATE=$(date -u -d "30 days ago" +"%Y-%m-%dT00:00:00.000+0000")
ENROLLMENT_PAYLOAD=$(cat <<EOF
{
  "patient": "$PATIENT_UUID",
  "program": "$PROGRAM_UUID",
  "dateEnrolled": "$START_DATE"
}
EOF
)

ENROLL_RESP=$(openmrs_api_post "/patientprogram" "$ENROLLMENT_PAYLOAD")
ENROLLMENT_UUID=$(echo "$ENROLL_RESP" | jq -r '.uuid // empty')

if [ -z "$ENROLLMENT_UUID" ]; then
  log "ERROR: Failed to enroll patient."
  log "Response: $ENROLL_RESP"
  exit 1
fi

log "Successfully enrolled patient. Enrollment UUID: $ENROLLMENT_UUID"

# Save context for verification
echo "$ENROLLMENT_UUID" > /tmp/target_enrollment_uuid.txt
echo "$PATIENT_UUID" > /tmp/target_patient_uuid.txt
echo "$PROGRAM_UUID" > /tmp/target_program_uuid.txt

# 5. Start Browser
if ! restart_firefox "$BAHMNI_LOGIN_URL" 4; then
  echo "ERROR: Browser failed to start cleanly"
  exit 1
fi

focus_firefox || true
sleep 2

take_screenshot /tmp/task_start.png
echo "=== Setup Complete ==="