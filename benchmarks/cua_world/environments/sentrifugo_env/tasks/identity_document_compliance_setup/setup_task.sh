#!/bin/bash
echo "=== Setting up identity_document_compliance_setup task ==="

source /workspace/scripts/task_utils.sh

# Wait for Sentrifugo HTTP to be ready
wait_for_http "$SENTRIFUGO_URL" 60

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# ---- Clean up any prior run artifacts ----
log "Cleaning up prior run artifacts for identity documents..."

# Delete employee identity documents to ensure a clean slate
docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -e \
    "DELETE FROM main_empidentitydocuments;" 2>/dev/null || true

# Delete the specific document types if they were created in a previous run
docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -e \
    "DELETE FROM main_identitydocuments WHERE name IN ('Passport', 'Work Visa');" 2>/dev/null || true

# Ensure EMP016, EMP017, EMP018 are active
for EMPID in EMP016 EMP017 EMP018; do
    docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -e \
        "UPDATE main_users SET isactive=1 WHERE employeeId='${EMPID}';" 2>/dev/null || true
done

# ---- Drop the compliance manifest on the Desktop ----
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/identity_documents_manifest.txt << 'MANIFEST'
COMPLIANCE MANIFEST: IDENTITY DOCUMENTS
---------------------------------------
The following identity documents must be configured in the HRMS:
1. Passport
2. Work Visa

Please update the following employee profiles with their verified document details:

Employee: EMP016 (Diego Silva)
- Passport: P-99482110 (Issued: 2024-01-15, Expires: 2034-01-14)
- Work Visa: V-5510098 (Issued: 2025-06-01, Expires: 2028-05-31)

Employee: EMP017 (Aisha Khan)
- Passport: P-77329001 (Issued: 2023-11-20, Expires: 2033-11-19)
- Work Visa: V-5510099 (Issued: 2025-06-01, Expires: 2028-05-31)

Employee: EMP018 (Liam O'Connor)
- Passport: P-44218876 (Issued: 2021-08-10, Expires: 2031-08-09)
- Work Visa: V-5510100 (Issued: 2025-06-01, Expires: 2028-05-31)
MANIFEST

chown ga:ga /home/ga/Desktop/identity_documents_manifest.txt
log "Compliance manifest created at ~/Desktop/identity_documents_manifest.txt"

# ---- Launch Firefox and navigate to dashboard ----
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/dashboard"
sleep 3

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial_state.png

log "Task ready: Manifest on Desktop, prior documents cleaned, logged into dashboard."
echo "=== identity_document_compliance_setup task setup complete ==="