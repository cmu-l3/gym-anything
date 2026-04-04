#!/bin/bash
echo "=== Setting up enterprise_hl7_router task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Copy all sample HL7 messages for testing
echo "Copying sample HL7 messages..."
cp /workspace/assets/hl7-v2.3-adt-a01-1.hl7 /home/ga/sample_adt_a01.hl7
cp /workspace/assets/hl7-v2.5-oru-critical-r01.hl7 /home/ga/sample_oru_lab.hl7
cp /workspace/assets/hl7-v2.5-oru-normal-r01.hl7 /home/ga/sample_oru_normal.hl7
chown ga:ga /home/ga/sample_adt_a01.hl7 /home/ga/sample_oru_lab.hl7 /home/ga/sample_oru_normal.hl7
chmod 644 /home/ga/sample_adt_a01.hl7 /home/ga/sample_oru_lab.hl7 /home/ga/sample_oru_normal.hl7

# Create all required PostgreSQL tables and seed routing_rules
echo "Creating database tables..."

docker exec nextgen-postgres psql -U postgres -d mirthdb -c "
CREATE TABLE IF NOT EXISTS routing_rules (
    rule_id SERIAL PRIMARY KEY,
    rule_name VARCHAR(100) NOT NULL,
    sending_app_pattern VARCHAR(100),
    message_type_pattern VARCHAR(50),
    destination_channel VARCHAR(200) NOT NULL,
    priority INTEGER DEFAULT 1,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT NOW()
);
" 2>/dev/null || true

docker exec nextgen-postgres psql -U postgres -d mirthdb -c "
INSERT INTO routing_rules (rule_name, sending_app_pattern, message_type_pattern, destination_channel, priority)
VALUES
    ('Lab Results Route', 'LabSystem', 'ORU', 'Lab Results Processor', 1),
    ('ADT Events Route', '%', 'ADT', 'ADT Event Handler', 2),
    ('Critical Lab Alert', 'CriticalLab', 'ORU', 'Lab Results Processor', 1),
    ('Generic ADT Route', 'Registration%', 'ADT', 'ADT Event Handler', 2)
ON CONFLICT DO NOTHING;
" 2>/dev/null || true

echo "routing_rules table created and seeded."

# NOTE: dead_letter_queue, lab_results_inbox, adt_events_inbox are NOT pre-created.
# The agent must create them (or the DB Writer destinations will create them on first INSERT).
# This is intentional: pre-creating them would give ambient credit in the do-nothing test.

# Verify routing_rules
echo "Verifying routing_rules:"
docker exec nextgen-postgres psql -U postgres -d mirthdb -c "\dt routing_rules;" 2>/dev/null || true
docker exec nextgen-postgres psql -U postgres -d mirthdb -c "SELECT rule_id, rule_name, message_type_pattern, destination_channel FROM routing_rules;" 2>/dev/null || true

# Record initial channel count
INITIAL_COUNT=$(get_channel_count)
rm -f /tmp/initial_entrouter_channel_count 2>/dev/null || sudo rm -f /tmp/initial_entrouter_channel_count 2>/dev/null || true
printf '%s' "$INITIAL_COUNT" > /tmp/initial_entrouter_channel_count 2>/dev/null || true

echo "Initial channel count: $INITIAL_COUNT"

# Open a terminal window for the agent to use
DISPLAY=:1 gnome-terminal --geometry=130x60+70+30 -- bash -c '
echo "========================================================"
echo " NextGen Connect - Enterprise HL7 Router (3-Channel)"
echo "========================================================"
echo ""
echo "ARCHITECTURE:"
echo "  External Systems -(any HL7)-> [Enterprise HL7 Router] (port 6668)"
echo "    |- MSH-3 contains Lab OR MSH-9 starts with ORU"
echo "    |    -> Channel Writer -> [Lab Results Processor]"
echo "    |                              -> lab_results_inbox table"
echo "    |- MSH-9 starts with ADT"
echo "    |    -> Channel Writer -> [ADT Event Handler]"
echo "    |                              -> adt_events_inbox table"
echo "    |- No match (default)"
echo "         -> DB Writer -> dead_letter_queue table"
echo ""
echo "The routing_rules table is already seeded (see below):"
echo "  docker exec nextgen-postgres psql -U postgres -d mirthdb -c 'SELECT * FROM routing_rules;'"
echo ""
echo "Tables already created by setup: routing_rules"
echo ""
echo "Tables YOU must create:"
echo "  dead_letter_queue (message_id, sending_app, message_type, raw_message, received_at)"
echo "  lab_results_inbox (message_id, patient_mrn, test_code, received_at)"
echo "  adt_events_inbox  (message_id, patient_mrn, event_type, received_at)"
echo ""
echo "  docker exec nextgen-postgres psql -U postgres -d mirthdb -c \\"
echo "    \"CREATE TABLE dead_letter_queue (message_id VARCHAR(100), sending_app VARCHAR(200),"
echo "     message_type VARCHAR(50), raw_message TEXT, received_at TIMESTAMP DEFAULT NOW());\""
echo ""
echo "IMPORTANT BUILD ORDER:"
echo "  1. Create + Deploy Channel 2: Lab Results Processor (get its ID)"
echo "  2. Create + Deploy Channel 3: ADT Event Handler (get its ID)"
echo "  3. Create + Deploy Channel 1: Enterprise HL7 Router"
echo "     - JS Transformer: extract MSH-3 -> sendingApp, MSH-9 -> messageType"
echo "     - Destination 1: Channel Writer (filter: ORU or Lab) -> Lab Results Processor ID"
echo "     - Destination 2: Channel Writer (filter: ADT) -> ADT Event Handler ID"
echo "     - Destination 3: DB Writer (no filter) -> dead_letter_queue"
echo ""
echo "Sample messages for testing:"
echo "  ADT: /home/ga/sample_adt_a01.hl7"
echo "  ORU (critical): /home/ga/sample_oru_lab.hl7"
echo "  ORU (normal):   /home/ga/sample_oru_normal.hl7"
echo ""
echo "Get channel IDs after creating them:"
echo "  curl -sk -u admin:admin -H \"X-Requested-With: OpenAPI\" \\"
echo "    https://localhost:8443/api/channels | python3 -c \\"
echo "    \"import sys,json; [print(c['\''id'\''],c['\''name'\'']) for c in json.load(sys.stdin)]\""
echo ""
echo "PostgreSQL (container): jdbc:postgresql://nextgen-postgres:5432/mirthdb"
echo "  User: postgres  Password: postgres"
echo "REST API: https://localhost:8443/api | admin:admin"
echo "  Required header: X-Requested-With: OpenAPI"
echo "========================================================"
echo ""
exec bash
' 2>/dev/null &

sleep 2
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

echo "=== Task setup complete ==="
