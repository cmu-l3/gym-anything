#!/bin/bash
set -e

echo "=== Setting up HospitalRun ==="

# ─── Phase 1: Prepare Docker Compose configuration ──────────────────────────
echo "[1/12] Preparing HospitalRun Docker configuration..."
mkdir -p /home/ga/hospitalrun
cp /workspace/config/docker-compose.yml /home/ga/hospitalrun/docker-compose.yml
chown -R ga:ga /home/ga/hospitalrun

# ─── Phase 2: Pull Docker images ────────────────────────────────────────────
echo "[2/12] Pulling Docker images..."
cd /home/ga/hospitalrun

# Pull images (Docker Hub may rate limit; retry logic included)
for img in "couchdb:1.7.1" "docker.elastic.co/elasticsearch/elasticsearch:5.6.16" "hospitalrun/hospitalrun-server:1.0.0-beta"; do
    for attempt in 1 2 3; do
        if docker pull "$img"; then
            echo "Pulled $img"
            break
        fi
        echo "Attempt $attempt failed for $img, retrying..."
        sleep 10
    done
done

# ─── Phase 2.5: Set vm.max_map_count for Elasticsearch ─────────────────────
# Elasticsearch 5.x requires vm.max_map_count >= 262144 when binding to non-loopback
echo "[2.5/12] Setting vm.max_map_count for Elasticsearch..."
sysctl -w vm.max_map_count=262144 || true
echo "vm.max_map_count is now: $(cat /proc/sys/vm/max_map_count)"

# ─── Phase 3: Start CouchDB and Elasticsearch first ─────────────────────────
echo "[3/12] Starting CouchDB and Elasticsearch..."
cd /home/ga/hospitalrun
docker compose up -d couchdb elasticsearch

# ─── Phase 4: Wait for CouchDB ──────────────────────────────────────────────
echo "[4/12] Waiting for CouchDB to be ready..."
COUCHDB_READY=0
for i in $(seq 1 60); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:5984/ 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        echo "CouchDB is ready (attempt $i)"
        COUCHDB_READY=1
        break
    fi
    sleep 3
done
if [ "$COUCHDB_READY" -eq 0 ]; then
    echo "ERROR: CouchDB failed to start"
    docker compose logs couchdb
    exit 1
fi

# ─── Phase 5: Initialize CouchDB (admin, databases, security) ────────────────
echo "[5/12] Initializing CouchDB..."
COUCHDB_URL="http://localhost:5984"

# Create admin user
curl -s -X PUT "${COUCHDB_URL}/_config/admins/couchadmin" -d '"test"' || true
SECURE_URL="http://couchadmin:test@localhost:5984"

# Small sleep to let admin take effect
sleep 2

# Setup _users security
curl -s -X PUT "${SECURE_URL}/_users/_security" \
    -H "Content-Type: application/json" \
    -d '{"admins":{"names":[],"roles":["admin"]},"members":{"names":[],"roles":["admin"]}}' || true

# Create config database
curl -s -X PUT "${SECURE_URL}/config" || true
curl -s -X PUT "${SECURE_URL}/config/_security" \
    -H "Content-Type: application/json" \
    -d '{"admins":{"names":[],"roles":["admin"]},"members":{"names":[],"roles":[]}}' || true

# Create main database
curl -s -X PUT "${SECURE_URL}/main" || true
curl -s -X PUT "${SECURE_URL}/main/_security" \
    -H "Content-Type: application/json" \
    -d '{"admins":{"names":[],"roles":["admin"]},"members":{"names":[],"roles":["user"]}}' || true

# Configure OAuth
curl -s -X PUT "${SECURE_URL}/_config/couch_httpd_oauth/use_users_db" -d '"true"' || true

# Enable CORS
curl -s -X PUT "${SECURE_URL}/_config/httpd/enable_cors" -d '"true"' || true
curl -s -X PUT "${SECURE_URL}/_config/cors/origins" -d '"*"' || true
curl -s -X PUT "${SECURE_URL}/_config/cors/methods" -d '"GET, PUT, POST, HEAD, DELETE"' || true
curl -s -X PUT "${SECURE_URL}/_config/cors/headers" -d '"accept, authorization, content-type, origin"' || true

# Create hradmin application user
# CRITICAL: "System Administrator" role is required for the navigation sidebar to appear
# "userPrefix" is used for patient ID generation in HospitalRun
HRADMIN_DOC=$(cat <<'EOF'
{
  "name": "hradmin",
  "password": "test",
  "roles": ["System Administrator", "admin", "user"],
  "type": "user",
  "userPrefix": "p1"
}
EOF
)
curl -s -X PUT "${SECURE_URL}/_users/org.couchdb.user:hradmin" \
    -H "Content-Type: application/json" \
    -d "${HRADMIN_DOC}" || true

echo "CouchDB initialization complete"

# ─── Phase 6: Wait for Elasticsearch ────────────────────────────────────────
# ES 5.x with single-node mode takes ~60-90s to start
echo "[6/12] Waiting for Elasticsearch to be ready (up to 3 min)..."
ES_READY=0
for i in $(seq 1 36); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9200/_cat/health 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        echo "Elasticsearch is ready (attempt $i)"
        ES_READY=1
        break
    fi
    sleep 5
done
if [ "$ES_READY" -eq 0 ]; then
    echo "WARNING: Elasticsearch not fully ready after 3 min, continuing (search features may not work)"
    docker logs hospitalrun-elasticsearch 2>&1 | tail -10 || true
fi

# ─── Phase 7: Start HospitalRun application ─────────────────────────────────
echo "[7/12] Starting HospitalRun application..."
cd /home/ga/hospitalrun
docker compose up -d hospitalrun

# ─── Phase 8: Wait for HospitalRun to initialize ────────────────────────────
# The entrypoint sleeps 40s then runs initcouch.sh again.
# We need to wait for the app itself to be available on port 3000.
echo "[8/12] Waiting for HospitalRun to be ready (this takes ~90s)..."
HR_READY=0
for i in $(seq 1 40); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/ 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
        echo "HospitalRun is ready on port 3000 (attempt $i)"
        HR_READY=1
        break
    fi
    sleep 5
done
if [ "$HR_READY" -eq 0 ]; then
    echo "WARNING: HospitalRun app not responding yet. Checking container logs..."
    docker compose logs --tail=30 hospitalrun || true
fi

# Give the entrypoint's initcouch.sh time to finish running
sleep 15

# ─── Phase 8.5: Fix PouchDB LOADING loop ─────────────────────────────────────
# ROOT CAUSE: _createRemoteDB() calls l.info() (GET /db/main) to verify the DB.
# The main CouchDB DB has _security requiring the "user" role, authenticated via
# OAuth headers stored in IndexedDB (pouch_config). Before login, there are no
# tokens → l.info() returns 401 → database.setup() rejects → LOADING forever.
#
# PRIMARY FIX: Remove the _security restriction from the main database so
# l.info() always returns 200 (regardless of login state). This allows
# database.setup() to complete on the first page load. After login, HospitalRun
# re-runs database.setup() with OAuth tokens for authenticated writes.
# The validate_doc_update design doc still enforces correct document format.
#
# SECONDARY FIX: patch config.js AND update CouchDB config doc for the offline
# sync setting. Do NOT restart the container: a restart destroys the ES index.
echo "[8.5/12] Fixing PouchDB LOADING issue (removing main DB security, patching config)..."

# Remove _security from main database — allows anonymous access for database.setup()
curl -s -X PUT "${SECURE_URL}/_config/httpd/enable_cors" -d '"true"' > /dev/null 2>&1 || true  # already set
curl -s -X PUT "http://couchadmin:test@localhost:5984/main/_security" \
    -H "Content-Type: application/json" \
    -d '{}' || true
echo "CouchDB main DB security restriction removed (anonymous access enabled)"

# Fix SRI: Remove the integrity attribute from index.html for the hospitalrun JS bundle.
# After patching the bundle (see Phase 8.5 bundle patch), its SHA512 hash changes.
# Firefox's Subresource Integrity (SRI) check would then refuse to execute the bundle
# → LOADING forever. Removing the integrity attribute lets Firefox load the patched bundle.
docker exec hospitalrun-app node -e "
var fs = require('fs');
var fpath = '/usr/src/app/node_modules/hospitalrun/prod/index.html';
var content = fs.readFileSync(fpath, 'utf8');
var patched = content.replace(/(src=\"\/assets\/hospitalrun-[^\"]*\.js\" )integrity=\"[^\"]*\"/, '\$1');
if (patched === content) {
    console.log('SRI: integrity already removed or not found');
} else {
    fs.writeFileSync(fpath, patched);
    console.log('SRI: Removed integrity attribute from hospitalrun JS bundle script tag');
}
" || true

# Patch config.js so future restarts also use the correct value.
# config.js uses 'module.exports = config;' (not 'module.exports = {'), so we
# insert the line before the 'config.serverInfo' property.
docker exec hospitalrun-app bash -c \
    "if grep -q 'disableOfflineSync' /usr/src/app/config.js; then
        echo 'config.js already patched'
    else
        sed -i 's/config\.serverInfo/config.disableOfflineSync = true;\nconfig.serverInfo/' /usr/src/app/config.js
        echo 'config.js patched OK'
    fi"

# Update CouchDB config doc directly — no restart needed
SECURE_URL2="http://couchadmin:test@localhost:5984"
CONFIG_DOC=$(curl -s "${SECURE_URL2}/config/config_disable_offline_sync" 2>/dev/null || echo '{}')
CONFIG_REV=$(echo "$CONFIG_DOC" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('_rev',''))" 2>/dev/null || echo "")

if [ -n "$CONFIG_REV" ]; then
    curl -s -X PUT "${SECURE_URL2}/config/config_disable_offline_sync" \
        -H "Content-Type: application/json" \
        -d "{\"_rev\":\"${CONFIG_REV}\",\"value\":true}" || true
else
    curl -s -X PUT "${SECURE_URL2}/config/config_disable_offline_sync" \
        -H "Content-Type: application/json" \
        -d '{"value":true}' || true
fi
echo "CouchDB config_disable_offline_sync set to true (no container restart)"
sleep 5

# ─── Phase 9: Seed realistic patient data into CouchDB ──────────────────────
echo "[9/12] Seeding patient and clinical data..."

# HospitalRun stores documents with:
#   _id: "<type>_<prefix>_<sequence>" (must have >= 3 underscore-separated parts)
#   data: { ...fields... }  (nested data object required by auth design doc)
# The auth design doc rejects docs unless _id.split('_').length >= 3 and doc.data exists.

seed_doc() {
    local id="$1"
    local doc="$2"
    local result
    result=$(curl -s -X PUT "${SECURE_URL}/main/${id}" \
        -H "Content-Type: application/json" \
        -d "${doc}" 2>/dev/null || echo '{"error":"curl failed"}')
    if echo "$result" | grep -q '"error"'; then
        echo "  WARN seeding ${id}: $result"
    fi
}

# Patient 1 - Margaret Chen, 58F, Hypertension
seed_doc "patient_p1_000001" '{
  "data": {
    "friendlyId": "P00001",
    "displayName": "Chen, Margaret",
    "firstName": "Margaret",
    "lastName": "Chen",
    "sex": "Female",
    "dateOfBirth": "03/14/1966",
    "bloodType": "A+",
    "status": "Active",
    "address": "412 Willow St, Springfield, IL 62701",
    "phone": "217-555-0142",
    "email": "margaret.chen@example.com",
    "patientType": "Outpatient"
  }
}'

# Patient 2 - James Okafor, 45M, Diabetes T2
seed_doc "patient_p1_000002" '{
  "data": {
    "friendlyId": "P00002",
    "displayName": "Okafor, James",
    "firstName": "James",
    "lastName": "Okafor",
    "sex": "Male",
    "dateOfBirth": "07/22/1979",
    "bloodType": "O+",
    "status": "Active",
    "address": "89 Maple Ave, Decatur, IL 62521",
    "phone": "217-555-0278",
    "email": "james.okafor@example.com",
    "patientType": "Outpatient"
  }
}'

# Patient 3 - Sofia Ramirez, 32F, Prenatal care
seed_doc "patient_p1_000003" '{
  "data": {
    "friendlyId": "P00003",
    "displayName": "Ramirez, Sofia",
    "firstName": "Sofia",
    "lastName": "Ramirez",
    "sex": "Female",
    "dateOfBirth": "11/05/1992",
    "bloodType": "B+",
    "status": "Active",
    "address": "234 Oak Blvd, Champaign, IL 61820",
    "phone": "217-555-0391",
    "email": "sofia.ramirez@example.com",
    "patientType": "Outpatient"
  }
}'

# Patient 4 - Harold Whitmore, 71M, CHF
seed_doc "patient_p1_000004" '{
  "data": {
    "friendlyId": "P00004",
    "displayName": "Whitmore, Harold",
    "firstName": "Harold",
    "lastName": "Whitmore",
    "sex": "Male",
    "dateOfBirth": "01/30/1953",
    "bloodType": "AB-",
    "status": "Active",
    "address": "56 Pine Circle, Peoria, IL 61602",
    "phone": "217-555-0467",
    "email": "harold.whitmore@example.com",
    "patientType": "Inpatient"
  }
}'

# Patient 5 - Aisha Patel, 29F, Asthma
seed_doc "patient_p1_000005" '{
  "data": {
    "friendlyId": "P00005",
    "displayName": "Patel, Aisha",
    "firstName": "Aisha",
    "lastName": "Patel",
    "sex": "Female",
    "dateOfBirth": "08/17/1995",
    "bloodType": "O-",
    "status": "Active",
    "address": "780 Elm St, Bloomington, IL 61701",
    "phone": "217-555-0583",
    "email": "aisha.patel@example.com",
    "patientType": "Outpatient"
  }
}'

# Patient 6 - Robert Kowalski, 52M, Back pain
seed_doc "patient_p1_000006" '{
  "data": {
    "friendlyId": "P00006",
    "displayName": "Kowalski, Robert",
    "firstName": "Robert",
    "lastName": "Kowalski",
    "sex": "Male",
    "dateOfBirth": "04/09/1972",
    "bloodType": "A-",
    "status": "Active",
    "address": "321 Cedar Ln, Rockford, IL 61101",
    "phone": "815-555-0612",
    "email": "robert.kowalski@example.com",
    "patientType": "Outpatient"
  }
}'

# Patient 7 - Linda Nakamura, 64F, Osteoarthritis
seed_doc "patient_p1_000007" '{
  "data": {
    "friendlyId": "P00007",
    "displayName": "Nakamura, Linda",
    "firstName": "Linda",
    "lastName": "Nakamura",
    "sex": "Female",
    "dateOfBirth": "12/03/1960",
    "bloodType": "B-",
    "status": "Active",
    "address": "903 Birch Ave, Aurora, IL 60505",
    "phone": "630-555-0729",
    "email": "linda.nakamura@example.com",
    "patientType": "Outpatient"
  }
}'

# Patient 8 - Carlos Mendoza, 38M, Hypertension
seed_doc "patient_p1_000008" '{
  "data": {
    "friendlyId": "P00008",
    "displayName": "Mendoza, Carlos",
    "firstName": "Carlos",
    "lastName": "Mendoza",
    "sex": "Male",
    "dateOfBirth": "06/20/1986",
    "bloodType": "O+",
    "status": "Active",
    "address": "445 Spruce St, Joliet, IL 60432",
    "phone": "815-555-0834",
    "email": "carlos.mendoza@example.com",
    "patientType": "Outpatient"
  }
}'

# Patient 9 - Dorothy Banks, 77F, Alzheimer early
seed_doc "patient_p1_000009" '{
  "data": {
    "friendlyId": "P00009",
    "displayName": "Banks, Dorothy",
    "firstName": "Dorothy",
    "lastName": "Banks",
    "sex": "Female",
    "dateOfBirth": "02/14/1947",
    "bloodType": "A+",
    "status": "Active",
    "address": "167 Poplar Rd, Evanston, IL 60201",
    "phone": "847-555-0956",
    "email": "dorothy.banks@example.com",
    "patientType": "Inpatient"
  }
}'

# Patient 10 - Marcus Williams, 41M, Appendectomy recovery
seed_doc "patient_p1_000010" '{
  "data": {
    "friendlyId": "P00010",
    "displayName": "Williams, Marcus",
    "firstName": "Marcus",
    "lastName": "Williams",
    "sex": "Male",
    "dateOfBirth": "09/28/1983",
    "bloodType": "AB+",
    "status": "Active",
    "address": "612 Walnut Dr, Naperville, IL 60540",
    "phone": "630-555-1071",
    "email": "marcus.williams@example.com",
    "patientType": "Inpatient"
  }
}'

# Patient 11 - Elena Petrov, 55F, Thyroid disorder
seed_doc "patient_p1_000011" '{
  "data": {
    "friendlyId": "P00011",
    "displayName": "Petrov, Elena",
    "firstName": "Elena",
    "lastName": "Petrov",
    "sex": "Female",
    "dateOfBirth": "05/11/1969",
    "bloodType": "A+",
    "status": "Active",
    "address": "28 Hickory Lane, Waukegan, IL 60085",
    "phone": "847-555-1182",
    "email": "elena.petrov@example.com",
    "patientType": "Outpatient"
  }
}'

# Patient 12 - Thomas Adeyemi, 33M, Sports injury
seed_doc "patient_p1_000012" '{
  "data": {
    "friendlyId": "P00012",
    "displayName": "Adeyemi, Thomas",
    "firstName": "Thomas",
    "lastName": "Adeyemi",
    "sex": "Male",
    "dateOfBirth": "10/07/1991",
    "bloodType": "O+",
    "status": "Active",
    "address": "394 Ash Street, Elgin, IL 60120",
    "phone": "847-555-1293",
    "email": "thomas.adeyemi@example.com",
    "patientType": "Outpatient"
  }
}'

# Patient 13 - Grace Kim, 48F, Migraine
seed_doc "patient_p1_000013" '{
  "data": {
    "friendlyId": "P00013",
    "displayName": "Kim, Grace",
    "firstName": "Grace",
    "lastName": "Kim",
    "sex": "Female",
    "dateOfBirth": "08/25/1976",
    "bloodType": "B+",
    "status": "Active",
    "address": "71 Chestnut Way, Schaumburg, IL 60193",
    "phone": "847-555-1304",
    "email": "grace.kim@example.com",
    "patientType": "Outpatient"
  }
}'

# Patient 14 - Arthur Jensen, 66M, COPD
seed_doc "patient_p1_000014" '{
  "data": {
    "friendlyId": "P00014",
    "displayName": "Jensen, Arthur",
    "firstName": "Arthur",
    "lastName": "Jensen",
    "sex": "Male",
    "dateOfBirth": "03/18/1958",
    "bloodType": "O-",
    "status": "Active",
    "address": "502 Sycamore Blvd, Downers Grove, IL 60515",
    "phone": "630-555-1415",
    "email": "arthur.jensen@example.com",
    "patientType": "Inpatient"
  }
}'

# Patient 15 - Priya Sharma, 27F, Appendicitis
seed_doc "patient_p1_000015" '{
  "data": {
    "friendlyId": "P00015",
    "displayName": "Sharma, Priya",
    "firstName": "Priya",
    "lastName": "Sharma",
    "sex": "Female",
    "dateOfBirth": "01/19/1997",
    "bloodType": "A-",
    "status": "Active",
    "address": "839 Magnolia Dr, Bolingbrook, IL 60440",
    "phone": "630-555-1526",
    "email": "priya.sharma@example.com",
    "patientType": "Outpatient"
  }
}'

echo "15 patients seeded"

# Seed visits for context - using proper _id format
seed_doc "visit_p1_000001" '{
  "data": {
    "patient": "patient_p1_000001",
    "visitType": "Outpatient",
    "startDate": "01/10/2025",
    "endDate": "01/10/2025",
    "examiner": "Dr. Sarah Mitchell",
    "location": "Clinic A",
    "reasonForVisit": "Blood pressure follow-up",
    "status": "completed"
  }
}'

seed_doc "visit_p1_000002" '{
  "data": {
    "patient": "patient_p1_000002",
    "visitType": "Outpatient",
    "startDate": "01/12/2025",
    "endDate": "01/12/2025",
    "examiner": "Dr. James Okonkwo",
    "location": "Clinic B",
    "reasonForVisit": "Diabetes management review",
    "status": "completed"
  }
}'

seed_doc "visit_p1_000003" '{
  "data": {
    "patient": "patient_p1_000003",
    "visitType": "Outpatient",
    "startDate": "01/15/2025",
    "endDate": "01/15/2025",
    "examiner": "Dr. Maria Santos",
    "location": "OB Clinic",
    "reasonForVisit": "Prenatal checkup - 28 weeks",
    "status": "completed"
  }
}'

seed_doc "visit_p1_000004" '{
  "data": {
    "patient": "patient_p1_000004",
    "visitType": "Inpatient",
    "startDate": "01/08/2025",
    "endDate": "01/11/2025",
    "examiner": "Dr. David Park",
    "location": "Ward 3",
    "reasonForVisit": "CHF exacerbation",
    "status": "admitted"
  }
}'

seed_doc "visit_p1_000005" '{
  "data": {
    "patient": "patient_p1_000005",
    "visitType": "Emergency",
    "startDate": "01/20/2025",
    "endDate": "01/20/2025",
    "examiner": "Dr. Lisa Nguyen",
    "location": "Emergency Department",
    "reasonForVisit": "Acute asthma exacerbation",
    "status": "completed"
  }
}'

echo "5 visits seeded"

# ─── Phase 9.5: Create CouchDB design documents (view indexes) ───────────────
# HospitalRun requires 31 view design documents in the main CouchDB database.
# These are normally created by the Ember.js/PouchDB client on the first browser
# load. We create them here so they're present in the checkpoint, avoiding the
# case where database.setup() queries a view that doesn't exist yet.
echo "[9.5/12] Creating CouchDB design documents (view indexes)..."
python3 << 'PYEOF'
import json, subprocess

BASE = "http://couchadmin:test@localhost:5984/main"

DOCS = {
"_design/appointments_by_date": {"views": {"appointments_by_date": {"map": 'function(doc) { var uidx; if (doc._id && (uidx = doc._id.indexOf("_")) > 0 && !doc.data.archived) { var doctype = doc._id.substring(0, uidx); if (doctype === "appointment") { var endDate = doc.data.endDate;\n    if (endDate && endDate !== "") {\n      endDate = new Date(endDate);\n      if (endDate.getTime) {\n        endDate = endDate.getTime();\n      }\n    }\n    var startDate = doc.data.startDate;\n    if (startDate && startDate !== "") {\n      startDate = new Date(startDate);\n      if (startDate.getTime) {\n        startDate = startDate.getTime();\n      }\n    }\n    if (doc.data.appointmentType !== "Surgery") {\n      emit([startDate, endDate, doc._id]);\n    } } } }'}}},
"_design/appointments_by_patient": {"views": {"appointments_by_patient": {"map": 'function(doc) { var uidx; if (doc._id && (uidx = doc._id.indexOf("_")) > 0 && !doc.data.archived) { var doctype = doc._id.substring(0, uidx); if (doctype === "appointment") { var endDate = doc.data.endDate;\n    if (endDate && endDate !== "") {\n      endDate = new Date(endDate);\n      if (endDate.getTime) {\n        endDate = endDate.getTime();\n      }\n    }\n    var startDate = doc.data.startDate;\n    if (startDate && startDate !== "") {\n      startDate = new Date(startDate);\n      if (startDate.getTime) {\n        startDate = startDate.getTime();\n      }\n    }\n    emit([doc.data.patient, startDate, endDate, doc._id]); } } }'}}},
"_design/closed_incidents_by_user": {"views": {"closed_incidents_by_user": {"map": 'function(doc) { var uidx; if (doc._id && (uidx = doc._id.indexOf("_")) > 0 && !doc.data.archived) { var doctype = doc._id.substring(0, uidx); if (doctype === "incident") { if (doc.data.status === "Closed") { emit([doc.data.reportedBy, doc._id]); } } } }'}}},
"_design/custom_form_by_type": {"views": {"custom_form_by_type": {"map": 'function(doc) { var uidx; if (doc._id && (uidx = doc._id.indexOf("_")) > 0 && !doc.data.archived) { var doctype = doc._id.substring(0, uidx); if (doctype === "customForm") { emit(doc.data.formType); } } }'}}},
"_design/imaging_by_status": {"views": {"imaging_by_status": {"map": 'function(doc) { var uidx; if (doc._id && (uidx = doc._id.indexOf("_")) > 0 && !doc.data.archived) { var doctype = doc._id.substring(0, uidx); if (doctype === "imaging") { var imagingDate = doc.data.imagingDate;\n    if (imagingDate && imagingDate !== "") {\n      imagingDate = new Date(imagingDate);\n      if (imagingDate.getTime) {\n        imagingDate = imagingDate.getTime();\n      }\n    }\n    var requestedDate = doc.data.requestedDate;\n    if (requestedDate && requestedDate !== "") {\n      requestedDate = new Date(requestedDate);\n      if (requestedDate.getTime) {\n        requestedDate = requestedDate.getTime();\n      }\n    }\n    emit([doc.data.status, requestedDate, imagingDate, doc._id]); } } }'}}},
"_design/incident_by_date": {"views": {"incident_by_date": {"map": 'function(doc) { var uidx; if (doc._id && (uidx = doc._id.indexOf("_")) > 0 && !doc.data.archived) { var doctype = doc._id.substring(0, uidx); if (doctype === "incident") { var dateOfIncident = doc.data.dateOfIncident;\n    if (dateOfIncident && dateOfIncident !== "") {\n      dateOfIncident = new Date(dateOfIncident);\n      if (dateOfIncident.getTime) {\n        dateOfIncident = dateOfIncident.getTime();\n      }\n    }\n    emit([dateOfIncident, doc._id]); } } }'}}},
"_design/incident_by_friendly_id": {"views": {"incident_by_friendly_id": {"map": 'function(doc) { var uidx; if (doc._id && (uidx = doc._id.indexOf("_")) > 0 && !doc.data.archived) { var doctype = doc._id.substring(0, uidx); if (doctype === "incident") { emit([doc.data.friendlyId, doc._id]); } } }'}}},
"_design/inventory_by_friendly_id": {"views": {"inventory_by_friendly_id": {"map": 'function(doc) { var uidx; if (doc._id && (uidx = doc._id.indexOf("_")) > 0 && !doc.data.archived) { var doctype = doc._id.substring(0, uidx); if (doctype === "inventory") { emit([doc.data.friendlyId, doc._id]); } } }'}}},
"_design/inventory_by_name": {"views": {"inventory_by_name": {"map": 'function(doc) { var uidx; if (doc._id && (uidx = doc._id.indexOf("_")) > 0 && !doc.data.archived) { var doctype = doc._id.substring(0, uidx); if (doctype === "inventory") { emit([doc.data.name, doc._id]); } } }'}}},
"_design/inventory_by_type": {"views": {"inventory_by_type": {"map": 'function(doc) { var uidx; if (doc._id && (uidx = doc._id.indexOf("_")) > 0 && !doc.data.archived) { var doctype = doc._id.substring(0, uidx); if (doctype === "inventory") { emit(doc.data.inventoryType); } } }'}}},
"_design/inventory_purchase_by_date_received": {"views": {"inventory_purchase_by_date_received": {"map": 'function(doc) { var uidx; if (doc._id && (uidx = doc._id.indexOf("_")) > 0 && !doc.data.archived) { var doctype = doc._id.substring(0, uidx); if (doctype === "invPurchase") { var dateReceived = doc.data.dateReceived;\n    if (dateReceived && dateReceived !== "") {\n      dateReceived = new Date(dateReceived);\n      if (dateReceived.getTime) {\n        dateReceived = dateReceived.getTime();\n      }\n    }\n    emit([dateReceived, doc._id]); } } }'}}},
"_design/inventory_purchase_by_expiration_date": {"views": {"inventory_purchase_by_expiration_date": {"map": 'function(doc) { var uidx; if (doc._id && (uidx = doc._id.indexOf("_")) > 0 && !doc.data.archived) { var doctype = doc._id.substring(0, uidx); if (doctype === "invPurchase") { var expirationDate = doc.data.expirationDate;\n    if (expirationDate && expirationDate !== "") {\n      expirationDate = new Date(expirationDate);\n      if (expirationDate.getTime) {\n        expirationDate = expirationDate.getTime();\n      }\n    }\n    emit([expirationDate, doc._id]); } } }'}}},
"_design/inventory_request_by_item": {"views": {"inventory_request_by_item": {"map": 'function(doc) { var uidx; if (doc._id && (uidx = doc._id.indexOf("_")) > 0 && !doc.data.archived) { var doctype = doc._id.substring(0, uidx); if (doctype === "invRequest") { var dateCompleted = doc.data.dateCompleted;\n    if (dateCompleted && dateCompleted !== "") {\n      dateCompleted = new Date(dateCompleted);\n      if (dateCompleted.getTime) {\n        dateCompleted = dateCompleted.getTime();\n      }\n    }\n    emit([doc.data.inventoryItem, doc.data.status, dateCompleted]); } } }'}}},
"_design/inventory_request_by_status": {"views": {"inventory_request_by_status": {"map": 'function(doc) { var uidx; if (doc._id && (uidx = doc._id.indexOf("_")) > 0 && !doc.data.archived) { var doctype = doc._id.substring(0, uidx); if (doctype === "invRequest") { var dateCompleted = doc.data.dateCompleted;\n    if (dateCompleted && dateCompleted !== "") {\n      dateCompleted = new Date(dateCompleted);\n      if (dateCompleted.getTime) {\n        dateCompleted = dateCompleted.getTime();\n      }\n    }\n    emit([doc.data.status, dateCompleted, doc._id]); } } }'}}},
"_design/invoice_by_patient": {"views": {"invoice_by_patient": {"map": 'function(doc) { var uidx; if (doc._id && (uidx = doc._id.indexOf("_")) > 0 && !doc.data.archived) { var doctype = doc._id.substring(0, uidx); if (doctype === "invoice") { emit(doc.data.patient); } } }'}}},
"_design/invoice_by_status": {"views": {"invoice_by_status": {"map": 'function(doc) { var uidx; if (doc._id && (uidx = doc._id.indexOf("_")) > 0 && !doc.data.archived) { var doctype = doc._id.substring(0, uidx); if (doctype === "invoice") { var billDate = doc.data.billDate;\n    if (billDate && billDate !== "") {\n      billDate = new Date(billDate);\n      if (billDate.getTime) {\n        billDate = billDate.getTime();\n      }\n    }\n    emit([doc.data.status, billDate, doc._id]); } } }'}}},
"_design/lab_by_status": {"views": {"lab_by_status": {"map": 'function(doc) { var uidx; if (doc._id && (uidx = doc._id.indexOf("_")) > 0 && !doc.data.archived) { var doctype = doc._id.substring(0, uidx); if (doctype === "lab") { var labDate = doc.data.labDate;\n    if (labDate && labDate !== "") {\n      labDate = new Date(labDate);\n      if (labDate.getTime) {\n        labDate = labDate.getTime();\n      }\n    }\n    var requestedDate = doc.data.requestedDate;\n    if (requestedDate && requestedDate !== "") {\n      requestedDate = new Date(requestedDate);\n      if (requestedDate.getTime) {\n        requestedDate = requestedDate.getTime();\n      }\n    }\n    emit([doc.data.status, requestedDate, labDate, doc._id]); } } }'}}},
"_design/medication_by_status": {"views": {"medication_by_status": {"map": 'function(doc) { var uidx; if (doc._id && (uidx = doc._id.indexOf("_")) > 0 && !doc.data.archived) { var doctype = doc._id.substring(0, uidx); if (doctype === "medication") { var prescriptionDate = doc.data.prescriptionDate;\n    if (prescriptionDate && prescriptionDate !== "") {\n      prescriptionDate = new Date(prescriptionDate);\n      if (prescriptionDate.getTime) {\n        prescriptionDate = prescriptionDate.getTime();\n      }\n    }\n    var requestedDate = doc.data.requestedDate;\n    if (requestedDate && requestedDate !== "") {\n      requestedDate = new Date(requestedDate);\n      if (requestedDate.getTime) {\n        requestedDate = requestedDate.getTime();\n      }\n    }\n    emit([doc.data.status, requestedDate, prescriptionDate, doc._id]); } } }'}}},
"_design/open_incidents_by_user": {"views": {"open_incidents_by_user": {"map": 'function(doc) { var uidx; if (doc._id && (uidx = doc._id.indexOf("_")) > 0 && !doc.data.archived) { var doctype = doc._id.substring(0, uidx); if (doctype === "incident") { if (doc.data.status !== "Closed") { emit([doc.data.reportedBy, doc._id]); } } } }'}}},
"_design/patient_by_admission": {"views": {"patient_by_admission": {"map": 'function(doc) { var uidx; if (doc._id && (uidx = doc._id.indexOf("_")) > 0 && !doc.data.archived) { var doctype = doc._id.substring(0, uidx); if (doctype === "patient") { if (doc.data.admitted === true) { if (doc.data.friendlyId) { emit([doc.data.friendlyId, doc._id]); } else if (doc.data.externalPatientId) { emit([doc.data.externalPatientId, doc._id]); } else { emit([doc._id, doc._id]); } } } } }'}}},
"_design/patient_by_display_id": {"views": {"patient_by_display_id": {"map": 'function(doc) { var uidx; if (doc._id && (uidx = doc._id.indexOf("_")) > 0 && !doc.data.archived) { var doctype = doc._id.substring(0, uidx); if (doctype === "patient") { if (doc.data.friendlyId) { emit([doc.data.friendlyId, doc._id]); } else if (doc.data.externalPatientId) { emit([doc.data.externalPatientId, doc._id]); } else { emit([doc._id, doc._id]); } } } }'}}},
"_design/patient_by_status": {"views": {"patient_by_status": {"map": 'function(doc) { var uidx; if (doc._id && (uidx = doc._id.indexOf("_")) > 0 && !doc.data.archived) { var doctype = doc._id.substring(0, uidx); if (doctype === "patient") { emit(doc.data.status); } } }'}}},
"_design/photo_by_patient": {"views": {"photo_by_patient": {"map": 'function(doc) { var uidx; if (doc._id && (uidx = doc._id.indexOf("_")) > 0 && !doc.data.archived) { var doctype = doc._id.substring(0, uidx); if (doctype === "photo") { emit(doc.data.patient); } } }'}}},
"_design/pricing_by_category": {"views": {"pricing_by_category": {"map": 'function(doc) { var uidx; if (doc._id && (uidx = doc._id.indexOf("_")) > 0 && !doc.data.archived) { var doctype = doc._id.substring(0, uidx); if (doctype === "pricing") { emit([doc.data.category, doc.data.name, doc.data.pricingType, doc._id]); } } }'}}},
"_design/procedure_by_date": {"views": {"procedure_by_date": {"map": 'function(doc) { var uidx; if (doc._id && (uidx = doc._id.indexOf("_")) > 0 && !doc.data.archived) { var doctype = doc._id.substring(0, uidx); if (doctype === "procedure") { var procedureDate = doc.data.procedureDate;\n    if (procedureDate && procedureDate !== "") {\n      procedureDate = new Date(procedureDate);\n      if (procedureDate.getTime) {\n        procedureDate = procedureDate.getTime();\n      }\n    }\n    emit([procedureDate, doc._id]); } } }'}}},
"_design/report_by_visit": {"views": {"report_by_visit": {"map": 'function(doc) { var uidx; if (doc._id && (uidx = doc._id.indexOf("_")) > 0 && !doc.data.archived) { var doctype = doc._id.substring(0, uidx); if (doctype === "report") { emit(doc.data.visit); } } }'}}},
"_design/sequence_by_prefix": {"views": {"sequence_by_prefix": {"map": 'function(doc) { var uidx; if (doc._id && (uidx = doc._id.indexOf("_")) > 0 && !doc.data.archived) { var doctype = doc._id.substring(0, uidx); if (doctype === "sequence") { emit(doc.data.prefix); } } }'}}},
"_design/surgical_appointments_by_date": {"views": {"surgical_appointments_by_date": {"map": 'function(doc) { var uidx; if (doc._id && (uidx = doc._id.indexOf("_")) > 0 && !doc.data.archived) { var doctype = doc._id.substring(0, uidx); if (doctype === "appointment") { var endDate = doc.data.endDate;\n    if (endDate && endDate !== "") {\n      endDate = new Date(endDate);\n      if (endDate.getTime) {\n        endDate = endDate.getTime();\n      }\n    }\n    var startDate = doc.data.startDate;\n    if (startDate && startDate !== "") {\n      startDate = new Date(startDate);\n      if (startDate.getTime) {\n        startDate = startDate.getTime();\n      }\n    }\n    if (doc.data.appointmentType === "Surgery") { emit([startDate, endDate, doc._id]); } } } }'}}},
"_design/visit_by_date": {"views": {"visit_by_date": {"map": 'function(doc) { var uidx; if (doc._id && (uidx = doc._id.indexOf("_")) > 0 && !doc.data.archived) { var doctype = doc._id.substring(0, uidx); if (doctype === "visit") { var endDate = doc.data.endDate;\n    if (endDate && endDate !== "") {\n      endDate = new Date(endDate);\n      if (endDate.getTime) {\n        endDate = endDate.getTime();\n      }\n    }\n    var startDate = doc.data.startDate;\n    if (startDate && startDate !== "") {\n      startDate = new Date(startDate);\n      if (startDate.getTime) {\n        startDate = startDate.getTime();\n      }\n    }\n    emit([startDate, endDate, doc._id]); } } }'}}},
"_design/visit_by_discharge_date": {"views": {"visit_by_discharge_date": {"map": 'function(doc) { var uidx; if (doc._id && (uidx = doc._id.indexOf("_")) > 0 && !doc.data.archived) { var doctype = doc._id.substring(0, uidx); if (doctype === "visit") { var endDate = doc.data.endDate;\n    if (endDate && endDate !== "") {\n      endDate = new Date(endDate);\n      if (endDate.getTime) {\n        endDate = endDate.getTime();\n      }\n    }\n    emit([endDate, doc._id]); } } }'}}},
"_design/visit_by_patient": {"views": {"visit_by_patient": {"map": 'function(doc) { var uidx; if (doc._id && (uidx = doc._id.indexOf("_")) > 0 && !doc.data.archived) { var doctype = doc._id.substring(0, uidx); if (doctype === "visit") { var endDate = doc.data.endDate;\n    if (endDate && endDate !== "") {\n      endDate = new Date(endDate);\n      if (endDate.getTime) {\n        endDate = endDate.getTime();\n      }\n    }\n    var startDate = doc.data.startDate;\n    if (startDate && startDate !== "") {\n      startDate = new Date(startDate);\n      if (startDate.getTime) {\n        startDate = startDate.getTime();\n      }\n    }\n    emit([doc.data.patient, startDate, endDate, doc.data.visitType, doc._id]); } } }'}}},
}

ok, warn = 0, 0
for doc_id, doc_body in DOCS.items():
    r = subprocess.run(["curl", "-s", f"{BASE}/{doc_id}"], capture_output=True, text=True)
    existing = json.loads(r.stdout)
    if "_rev" in existing:
        doc_body["_rev"] = existing["_rev"]
    doc_body["_id"] = doc_id
    put = subprocess.run(
        ["curl", "-s", "-X", "PUT", f"{BASE}/{doc_id}",
         "-H", "Content-Type: application/json",
         "-d", json.dumps(doc_body)],
        capture_output=True, text=True
    )
    resp = json.loads(put.stdout)
    if "error" in resp:
        print(f"  WARN {doc_id}: {resp}")
        warn += 1
    else:
        ok += 1

print(f"Design documents: {ok} created/updated, {warn} warnings")
PYEOF

# ─── Phase 10: Configure Firefox profile ─────────────────────────────────────
echo "[10/12] Configuring Firefox browser..."

# Warm-up Firefox to create snap profile
su - ga -c "DISPLAY=:1 firefox --headless &" 2>/dev/null || \
su - ga -c "DISPLAY=:1 firefox &" 2>/dev/null || true
sleep 12
pkill -f firefox || true
sleep 3

# Find the Firefox profile (snap or standard)
FF_PROFILE_DIR=""
# Try snap Firefox profile first
if [ -d /home/ga/snap/firefox/common/.mozilla/firefox ]; then
    FF_PROFILE_DIR=$(find /home/ga/snap/firefox/common/.mozilla/firefox -maxdepth 1 -name '*.default*' -type d 2>/dev/null | head -1)
fi
# Fallback to standard Firefox profile
if [ -z "$FF_PROFILE_DIR" ] && [ -d /home/ga/.mozilla/firefox ]; then
    FF_PROFILE_DIR=$(find /home/ga/.mozilla/firefox -maxdepth 1 -name '*.default*' -type d 2>/dev/null | head -1)
fi

if [ -n "$FF_PROFILE_DIR" ]; then
    echo "Found Firefox profile at: $FF_PROFILE_DIR"
    cat > "${FF_PROFILE_DIR}/user.js" << 'FFEOF'
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.startup.homepage", "http://localhost:3000");
user_pref("browser.startup.page", 1);
user_pref("signon.rememberSignons", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutConfig.showWarning", false);
user_pref("network.prefetch-next", false);
user_pref("browser.download.manager.showWhenStarting", false);
FFEOF
    chown ga:ga "${FF_PROFILE_DIR}/user.js"
    echo "Firefox profile configured"
else
    echo "WARNING: Could not find Firefox profile directory"
fi

# ─── Phase 11: Launch Firefox with HospitalRun ───────────────────────────────
echo "[11/12] Launching Firefox to HospitalRun..."
su - ga -c "DISPLAY=:1 firefox http://localhost:3000 &" 2>/dev/null || true
sleep 10

# Maximize Firefox window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# ─── Phase 12: Save API token for task utilities ─────────────────────────────
echo "[12/12] Saving configuration for task utilities..."
mkdir -p /home/ga/hospitalrun
cat > /home/ga/hospitalrun/config.sh << 'CONFIGEOF'
# HospitalRun configuration for task utilities
export HR_URL="http://localhost:3000"
export HR_COUCH_URL="http://couchadmin:test@localhost:5984"
export HR_COUCH_MAIN_DB="main"
export HR_USER="hradmin"
export HR_PASS="test"
CONFIGEOF
chown ga:ga /home/ga/hospitalrun/config.sh

echo "=== HospitalRun setup complete ==="
echo "Access at: http://localhost:3000"
echo "Username: hradmin / Password: test"
