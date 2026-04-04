#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up complete_imaging_request task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# ─── 1. Determine CouchDB URL ───────────────────────────────────────────────
# Use admin credentials if needed (handled in task_utils but explicitly setting for local curls)
COUCH_BASE="http://couchadmin:test@localhost:5984"

# ─── 2. Ensure Dependencies (Patient & Pricing) ─────────────────────────────

# Create Patient: Maria Garcia (P00001)
echo "Ensuring patient Maria Garcia exists..."
hr_couch_put "patient_p1_0000001" '{
  "data": {
    "firstName": "Maria",
    "lastName": "Garcia",
    "sex": "Female",
    "dateOfBirth": "1985-07-22T00:00:00.000Z",
    "patientId": "P00001",
    "address": "742 Evergreen Terrace, Springfield, IL 62704",
    "phone": "555-0147",
    "email": "maria.garcia@email.com"
  }
}'

# Create Pricing Item: Chest X-Ray (needed for Imaging Type lookup)
echo "Ensuring pricing item exists..."
hr_couch_put "pricing_p1_imaging001" '{
  "data": {
    "name": "Chest X-Ray PA/Lateral",
    "category": "Imaging",
    "price": 150.00,
    "pricingType": "Imaging"
  }
}'

# ─── 3. Reset Imaging Request ───────────────────────────────────────────────
# Always reset to "Requested" status and empty result
echo "Resetting imaging request..."
hr_couch_put "imaging_p1_0000001" '{
  "data": {
    "patient": "patient_p1_0000001",
    "imagingType": "pricing_p1_imaging001",
    "imagingDateAsTime": 1731667800000,
    "requestedBy": "Dr. James Rodriguez",
    "requestedDate": "2024-11-15T10:30:00.000Z",
    "status": "Requested",
    "notes": "Rule out pneumonia. Patient presents with persistent cough for 2 weeks, low-grade fever.",
    "result": ""
  }
}'

# ─── 4. Record Initial State for Anti-Gaming ────────────────────────────────
echo "Recording initial document revision..."
INITIAL_REV=$(curl -s "${COUCH_BASE}/main/imaging_p1_0000001" | python3 -c "import sys, json; print(json.load(sys.stdin).get('_rev', ''))")
echo "$INITIAL_REV" > /tmp/initial_imaging_rev.txt
echo "Initial Rev: $INITIAL_REV"

# ─── 5. Prepare Application ─────────────────────────────────────────────────
# Fix infinite loading issue common in this environment
fix_offline_sync

# Ensure HospitalRun is ready
ensure_hospitalrun_ready

# Launch Firefox to HospitalRun
# We start at the dashboard; agent must navigate to Imaging
navigate_firefox_to "http://localhost:3000/"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="