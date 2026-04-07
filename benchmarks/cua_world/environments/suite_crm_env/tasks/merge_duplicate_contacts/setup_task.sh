#!/bin/bash
echo "=== Setting up merge_duplicate_contacts task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt 2>/dev/null || true

# Prepare the data using a Python helper to ensure robust SQL generation and execution
cat << 'EOF' > /tmp/setup_helper.py
import subprocess
import uuid
import json

def run_query(query):
    cmd = ["docker", "exec", "-i", "suitecrm-db", "mysql", "-u", "suitecrm", "-psuitecrm_pass", "suitecrm"]
    subprocess.run(cmd, input=query.encode('utf-8'), check=True, stderr=subprocess.DEVNULL)

# Clean up any existing records with this name to avoid conflicts
run_query("UPDATE contacts SET deleted=1 WHERE first_name='Maria' AND last_name='Thornton-Garcia';")

# Generate UUIDs for Contact A (Older Record)
uuid_a = str(uuid.uuid4())
email_uuid_a = str(uuid.uuid4())
rel_uuid_a = str(uuid.uuid4())

query_a = f"""
INSERT INTO contacts (id, date_entered, date_modified, modified_user_id, created_by, deleted, first_name, last_name, title, primary_address_street, primary_address_city, primary_address_state, primary_address_postalcode, description)
VALUES ('{uuid_a}', DATE_SUB(NOW(), INTERVAL 1 YEAR), DATE_SUB(NOW(), INTERVAL 1 YEAR), '1', '1', 0, 'Maria', 'Thornton-Garcia', 'Purchasing Coordinator', '2847 Riverside Dr', 'Portland', 'OR', '97201', 'Initial contact from trade show 2023');

INSERT INTO email_addresses (id, email_address, email_address_caps, invalid_email, opt_out, date_created, date_modified, deleted)
VALUES ('{email_uuid_a}', 'maria.thorntongarcia@globalwidgets.com', 'MARIA.THORNTONGARCIA@GLOBALWIDGETS.COM', 0, 0, NOW(), NOW(), 0);

INSERT INTO email_addr_bean_rel (id, email_address_id, bean_id, bean_module, primary_address, reply_to_address, date_created, date_modified, deleted)
VALUES ('{rel_uuid_a}', '{email_uuid_a}', '{uuid_a}', 'Contacts', 1, 0, NOW(), NOW(), 0);
"""
run_query(query_a)

# Generate UUIDs for Contact B (Newer Record)
uuid_b = str(uuid.uuid4())
email_uuid_b = str(uuid.uuid4())
rel_uuid_b = str(uuid.uuid4())

query_b = f"""
INSERT INTO contacts (id, date_entered, date_modified, modified_user_id, created_by, deleted, first_name, last_name, title, phone_work, primary_address_street, primary_address_city, primary_address_state, primary_address_postalcode, description)
VALUES ('{uuid_b}', DATE_SUB(NOW(), INTERVAL 1 MONTH), DATE_SUB(NOW(), INTERVAL 1 MONTH), '1', '1', 0, 'Maria', 'Thornton-Garcia', 'Senior Purchasing Manager', '(503) 555-8192', '1520 Innovation Blvd Suite 300', 'Portland', 'OR', '97209', 'Updated contact from Q2 2024 renewal call');

INSERT INTO email_addresses (id, email_address, email_address_caps, invalid_email, opt_out, date_created, date_modified, deleted)
VALUES ('{email_uuid_b}', 'mtgarcia.personal@gmail.com', 'MTGARCIA.PERSONAL@GMAIL.COM', 0, 0, NOW(), NOW(), 0);

INSERT INTO email_addr_bean_rel (id, email_address_id, bean_id, bean_module, primary_address, reply_to_address, date_created, date_modified, deleted)
VALUES ('{rel_uuid_b}', '{email_uuid_b}', '{uuid_b}', 'Contacts', 1, 0, NOW(), NOW(), 0);
"""
run_query(query_b)

# Save the target UUIDs for rigorous verifier checking
with open("/tmp/task_uuids.json", "w") as f:
    json.dump({"uuid_a": uuid_a, "uuid_b": uuid_b}, f)
EOF

python3 /tmp/setup_helper.py
chmod 666 /tmp/task_uuids.json 2>/dev/null || true

# Ensure logged in and navigate to Contacts list where the duplicate can be seen
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Contacts&action=index"
sleep 4

# Take initial screenshot for evidence
take_screenshot /tmp/merge_duplicate_contacts_initial.png

echo "=== setup complete ==="