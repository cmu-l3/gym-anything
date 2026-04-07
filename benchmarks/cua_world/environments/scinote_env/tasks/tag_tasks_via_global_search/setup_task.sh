#!/bin/bash
echo "=== Setting up tag_tasks_via_global_search task ==="

# Clean up previous task files
rm -f /tmp/tag_tasks_result.json 2>/dev/null || true
rm -f /tmp/target_task_ids.txt 2>/dev/null || true
rm -f /tmp/task_start_time.txt 2>/dev/null || true

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for DB to be ready
ensure_docker_healthy
wait_for_scinote_ready 60

echo "=== Creating prerequisite projects, experiments, and tasks ==="

# Helper function to create the nested experiment structure
create_task_env() {
    local proj_name="$1"
    local exp_name="$2"
    local task_name="$3"
    
    # Create Project
    scinote_db_query "INSERT INTO projects (name, visibility, team_id, created_by_id, created_at, updated_at, archived, demo) VALUES ('${proj_name}', 1, 1, 1, NOW(), NOW(), false, false);" > /dev/null
    local p_id=$(scinote_db_query "SELECT id FROM projects WHERE name='${proj_name}' ORDER BY id DESC LIMIT 1;" | tr -d '[:space:]')
    ensure_user_assignment "Project" "$p_id"
    
    # Create Experiment
    scinote_db_query "INSERT INTO experiments (name, project_id, created_by_id, last_modified_by_id, created_at, updated_at) VALUES ('${exp_name}', $p_id, 1, 1, NOW(), NOW());" > /dev/null
    local e_id=$(scinote_db_query "SELECT id FROM experiments WHERE name='${exp_name}' AND project_id=$p_id ORDER BY id DESC LIMIT 1;" | tr -d '[:space:]')
    ensure_user_assignment "Experiment" "$e_id"
    
    # Create Task
    scinote_db_query "INSERT INTO my_modules (name, experiment_id, created_by_id, created_at, updated_at) VALUES ('${task_name}', $e_id, 1, NOW(), NOW());" > /dev/null
    local t_id=$(scinote_db_query "SELECT id FROM my_modules WHERE name='${task_name}' AND experiment_id=$e_id ORDER BY id DESC LIMIT 1;" | tr -d '[:space:]')
    ensure_user_assignment "MyModule" "$t_id"
    
    # Initialize empty protocol for the task
    scinote_db_query "INSERT INTO protocols (my_module_id, team_id, protocol_type, created_at, updated_at, archived) VALUES ($t_id, 1, 0, NOW(), NOW(), false);" > /dev/null
    
    echo "$t_id"
}

# Project 1
T1_ID=$(create_task_env "Immunology Study" "Cell Line Maintenance" "Media Prep (Lot FBS-774B)")
E1_ID=$(scinote_db_query "SELECT experiment_id FROM my_modules WHERE id=$T1_ID;" | tr -d '[:space:]')
scinote_db_query "INSERT INTO my_modules (name, experiment_id, created_by_id, created_at, updated_at) VALUES ('Cell Passaging', $E1_ID, 1, NOW(), NOW());" > /dev/null
N1_ID=$(scinote_db_query "SELECT id FROM my_modules WHERE name='Cell Passaging' AND experiment_id=$E1_ID ORDER BY id DESC LIMIT 1;" | tr -d '[:space:]')
ensure_user_assignment "MyModule" "$N1_ID"
scinote_db_query "INSERT INTO protocols (my_module_id, team_id, protocol_type, created_at, updated_at, archived) VALUES ($N1_ID, 1, 0, NOW(), NOW(), false);" > /dev/null

# Project 2
T2_ID=$(create_task_env "Vaccine Development" "In vitro testing" "Lot FBS-774B Cell Culture")
E2_ID=$(scinote_db_query "SELECT experiment_id FROM my_modules WHERE id=$T2_ID;" | tr -d '[:space:]')
scinote_db_query "INSERT INTO my_modules (name, experiment_id, created_by_id, created_at, updated_at) VALUES ('Viral Titration', $E2_ID, 1, NOW(), NOW());" > /dev/null
N2_ID=$(scinote_db_query "SELECT id FROM my_modules WHERE name='Viral Titration' AND experiment_id=$E2_ID ORDER BY id DESC LIMIT 1;" | tr -d '[:space:]')
ensure_user_assignment "MyModule" "$N2_ID"
scinote_db_query "INSERT INTO protocols (my_module_id, team_id, protocol_type, created_at, updated_at, archived) VALUES ($N2_ID, 1, 0, NOW(), NOW(), false);" > /dev/null

# Project 3
T3_ID=$(create_task_env "Quality Control" "Reagent Testing" "Transfection - Lot FBS-774B")
E3_ID=$(scinote_db_query "SELECT experiment_id FROM my_modules WHERE id=$T3_ID;" | tr -d '[:space:]')
scinote_db_query "INSERT INTO my_modules (name, experiment_id, created_by_id, created_at, updated_at) VALUES ('Endotoxin Assay', $E3_ID, 1, NOW(), NOW());" > /dev/null
N3_ID=$(scinote_db_query "SELECT id FROM my_modules WHERE name='Endotoxin Assay' AND experiment_id=$E3_ID ORDER BY id DESC LIMIT 1;" | tr -d '[:space:]')
ensure_user_assignment "MyModule" "$N3_ID"
scinote_db_query "INSERT INTO protocols (my_module_id, team_id, protocol_type, created_at, updated_at, archived) VALUES ($N3_ID, 1, 0, NOW(), NOW(), false);" > /dev/null

# Save the target IDs for the verifier to check against
echo "$T1_ID,$T2_ID,$T3_ID" > /tmp/target_task_ids.txt
echo "Target tasks created with IDs: $T1_ID, $T2_ID, $T3_ID"
echo "Noise tasks created with IDs: $N1_ID, $N2_ID, $N3_ID"

# Ensure Firefox is running at the login page
ensure_firefox_running "${SCINOTE_URL}/users/sign_in"

sleep 3
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="