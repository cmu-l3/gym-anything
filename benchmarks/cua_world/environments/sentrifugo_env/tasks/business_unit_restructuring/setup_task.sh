#!/bin/bash
echo "=== Setting up business_unit_restructuring task ==="

source /workspace/scripts/task_utils.sh

# Wait for Sentrifugo web service to be fully ready
wait_for_http "$SENTRIFUGO_URL" 60

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/task_start_time.txt

log "Resetting Database to Initial State..."

# 1. Ensure primary BU exists and is named "Acme Corp HQ"
docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -e \
    "UPDATE main_businessunits SET unitname='Acme Corp HQ', isactive=1 WHERE id=1;" 2>/dev/null || true

# 2. Delete any prior instance of "Acme Corp Technology"
docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -e \
    "DELETE FROM main_businessunits WHERE unitname='Acme Corp Technology';" 2>/dev/null || true

# 3. Ensure all 10 departments exist, are active, and belong to "Acme Corp HQ" (unitid=1)
DEPTS=(
    "Engineering" "Data Science" "DevOps & Infrastructure" "Quality Assurance" 
    "Sales" "Marketing" "Finance & Accounting" "Human Resources" 
    "Customer Support" "Product Development"
)

for d in "${DEPTS[@]}"; do
    # Check if department exists
    EXISTS=$(docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -e "SELECT id FROM main_departments WHERE deptname='$d' LIMIT 1;" | tr -d '[:space:]')
    
    if [ -z "$EXISTS" ]; then
        # Insert missing department
        CODE=$(echo "$d" | awk '{print toupper(substr($1,1,3))}')
        docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -e \
            "INSERT INTO main_departments (deptname, deptcode, unitid, isactive) VALUES ('$d', '${CODE}', 1, 1);" 2>/dev/null || true
    else
        # Update existing department to point to HQ
        docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -e \
            "UPDATE main_departments SET unitid=1, isactive=1 WHERE id=$EXISTS;" 2>/dev/null || true
    fi
done

log "Database reset complete. All 10 departments are currently assigned to 'Acme Corp HQ'."

# ---- Drop restructuring memo on Desktop ----
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/restructuring_memo.txt << 'MEMO'
CONFIDENTIAL — BOARD DIRECTIVE #2026-003
Strategic Business Unit Restructuring

Effective Date: February 1, 2026

The Board of Directors has approved the following organizational restructuring:

1. CREATE a new Business Unit: "Acme Corp Technology"
   - Status: Active
   - Start Date: 2026-02-01

2. TRANSFER the following departments from "Acme Corp HQ" to "Acme Corp Technology":
   - Engineering
   - Data Science
   - DevOps & Infrastructure
   - Quality Assurance

3. The following departments REMAIN under "Acme Corp HQ" (DO NOT MOVE):
   - Sales
   - Marketing
   - Finance & Accounting
   - Human Resources
   - Customer Support
   - Product Development

This restructuring supports our strategy to create a dedicated technology
arm while maintaining business operations under the existing HQ structure.

Implementation must be completed in the Sentrifugo HRMS by end of business today.

Authorized by: Board of Directors, Acme Corp
MEMO

chown ga:ga /home/ga/Desktop/restructuring_memo.txt
log "Restructuring memo created at ~/Desktop/restructuring_memo.txt"

# ---- Launch Firefox and navigate to Sentrifugo ----
log "Launching browser..."
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/index.php/organization/businessunits"
sleep 5

# ---- Take Initial Evidence Screenshot ----
take_screenshot /tmp/task_initial.png

log "Task ready: initial state configured and UI focused."
echo "=== Setup complete ==="