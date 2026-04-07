#!/bin/bash
echo "=== Setting up hl7_to_html_bed_card_db_lookup task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Prepare Database (Create table and insert data)
echo "Setting up database tables..."
# Check if table exists, if not create it
docker exec nextgen-postgres psql -U postgres -d mirthdb -c "
CREATE TABLE IF NOT EXISTS doctors (
    doctor_id VARCHAR(20) PRIMARY KEY,
    full_name VARCHAR(100)
);" 2>/dev/null

# Insert sample data (upsert style to avoid dupes)
docker exec nextgen-postgres psql -U postgres -d mirthdb -c "
TRUNCATE doctors;
INSERT INTO doctors (doctor_id, full_name) VALUES 
('DOC101', 'Dr. Gregory House'),
('DOC202', 'Dr. Lisa Cuddy'),
('DOC303', 'Dr. James Wilson');
" 2>/dev/null

echo "Database initialized with doctor records."

# 2. Create Output Directory
mkdir -p /home/ga/bed_cards
chmod 777 /home/ga/bed_cards

# 3. Create Sample HL7 Message for Agent
cat > /home/ga/sample_adt.hl7 <<EOF
MSH|^~\\&|EPIC|HOSP|MIRTH|PC|202310270900||ADT^A01|MSG001|P|2.3
PID|||12345^^^HOSP^MR||DOE^JANE||19800101|F
PV1||I|3N^301^A||||DOC101^HOUSE^GREGORY||||||||||||||||||||||||||||||||||||202310270900
EOF
chown ga:ga /home/ga/sample_adt.hl7

# 4. Record Initial State
INITIAL_CHANNEL_COUNT=$(get_channel_count)
echo "$INITIAL_CHANNEL_COUNT" > /tmp/initial_channel_count

# 5. Open Terminal with Instructions
DISPLAY=:1 gnome-terminal --geometry=100x30+50+50 -- bash -c '
echo "======================================================="
echo " TASK: Generate Patient Bed Cards with Database Lookup"
echo "======================================================="
echo ""
echo "GOAL: Create a channel that:"
echo "  1. Receives HL7 ADT messages on Port 6661"
echo "  2. Looks up the Doctor Name in the DB using PV1-7.1 ID"
echo "  3. Generates an HTML file in /home/ga/bed_cards/"
echo ""
echo "DATABASE INFO (PostgreSQL inside container):"
echo "  URL: jdbc:postgresql://nextgen-postgres:5432/mirthdb"
echo "  User: postgres"
echo "  Pass: postgres"
echo "  Table: doctors (doctor_id, full_name)"
echo ""
echo "SAMPLE DATA:"
echo "  DOC101 -> Dr. Gregory House"
echo "  DOC202 -> Dr. Lisa Cuddy"
echo ""
echo "REST API: https://localhost:8443/api (admin/admin)"
echo "Required Header: X-Requested-With: OpenAPI"
echo ""
echo "Sample message created at: /home/ga/sample_adt.hl7"
echo ""
exec bash
' 2>/dev/null &

# 6. Ensure Firefox is open
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox http://localhost:8080 &"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="