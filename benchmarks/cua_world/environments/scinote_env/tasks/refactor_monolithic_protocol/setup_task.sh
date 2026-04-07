#!/bin/bash
echo "=== Setting up refactor_monolithic_protocol task ==="

source /workspace/scripts/task_utils.sh

rm -f /tmp/refactor_protocol_result.json 2>/dev/null || true

# Wait for SciNote container and database to be ready
wait_for_scinote_ready 60

echo "Creating protocol and monolithic step..."

# Insert Protocol using SQL to avoid any Rails model validation issues
TEAM_ID=$(scinote_db_query "SELECT id FROM teams LIMIT 1;" | tr -d '[:space:]')
if [ -z "$TEAM_ID" ]; then TEAM_ID=1; fi

# Delete existing records to ensure clean state on task retry
scinote_db_query "DELETE FROM protocols WHERE name='Bradford Protein Assay (Draft)' AND my_module_id IS NULL;"

# Insert new protocol
scinote_db_query "INSERT INTO protocols (name, team_id, protocol_type, created_at, updated_at, archived) VALUES ('Bradford Protein Assay (Draft)', $TEAM_ID, 0, NOW(), NOW(), false);"
PROTO_ID=$(scinote_db_query "SELECT id FROM protocols WHERE name='Bradford Protein Assay (Draft)' AND my_module_id IS NULL ORDER BY id DESC LIMIT 1;" | tr -d '[:space:]')

# Insert single step
scinote_db_query "INSERT INTO steps (name, protocol_id, position, created_at, updated_at, step_duration) VALUES ('Full Procedure', $PROTO_ID, 1, NOW(), NOW(), 0);"
STEP_ID=$(scinote_db_query "SELECT id FROM steps WHERE protocol_id=$PROTO_ID ORDER BY id DESC LIMIT 1;" | tr -d '[:space:]')

# Prepare text content
TEXT_CONTENT="Prepare BSA protein standards ranging from 0 to 2000 ug/mL using the same buffer as the unknown samples. WARNING: Coomassie dye is highly acidic and stains skin and clothing; wear gloves and a lab coat. Dilute unknown protein samples 1:10 and 1:100 in buffer to ensure they fall within the linear range of the standard curve. In a 96-well microplate, add 5 uL of each standard or sample into respective wells in triplicate. Add 250 uL of room-temperature Bradford Reagent to each well and mix thoroughly on a plate shaker for 30 seconds. Incubate the microplate at room temperature for exactly 5 minutes. Measure the absorbance at 595 nm using a microplate reader. Calculate protein concentrations using the standard curve."

# Insert into step_texts
scinote_db_query "INSERT INTO step_texts (text, created_at, updated_at) VALUES ('$TEXT_CONTENT', NOW(), NOW());"
TEXT_ID=$(scinote_db_query "SELECT id FROM step_texts ORDER BY id DESC LIMIT 1;" | tr -d '[:space:]')

# Link text to step
scinote_db_query "UPDATE step_texts SET step_id=$STEP_ID WHERE id=$TEXT_ID;" 2>/dev/null || true
scinote_db_query "INSERT INTO step_orderable_elements (orderable_type, orderable_id, step_id, position, created_at, updated_at) VALUES ('StepText', $TEXT_ID, $STEP_ID, 1, NOW(), NOW());" 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure Firefox is running
ensure_firefox_running "${SCINOTE_URL}/users/sign_in"

sleep 3
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="