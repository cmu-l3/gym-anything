#!/bin/bash
echo "=== Setting up locate_experiments_via_search task ==="

# Clean up previous task files
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /home/ga/Documents/vorinostat_experiments.txt 2>/dev/null || true
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Creating test data (Projects, Experiments, Results) ==="

# Create a robust Ruby script to initialize data and trigger search index callbacks
cat > /tmp/setup_search_data.rb << 'EOF'
begin
  team = Team.first || Team.new(name: "Default Team")
  user = User.find_by(email: 'admin@scinote.net') || User.first
  role = UserRole.find_by(name: 'Owner', predefined: true) || UserRole.first

  p1 = Project.create!(name: 'Cutaneous T-Cell Lymphoma', team: team, created_by: user)
  UserAssignment.create!(assignable: p1, user: user, user_role: role, team: team) rescue nil
  e1 = Experiment.create!(name: 'Vorinostat Efficacy Study VR-01', project: p1, created_by: user, last_modified_by: user)
  UserAssignment.create!(assignable: e1, user: user, user_role: role, team: team) rescue nil

  p2 = Project.create!(name: 'Phase I Safety Trials', team: team, created_by: user)
  UserAssignment.create!(assignable: p2, user: user, user_role: role, team: team) rescue nil
  e2 = Experiment.create!(name: 'PK Profile - Group 4', description: '<p>Testing PK profile of Vorinostat in Group 4</p>', project: p2, created_by: user, last_modified_by: user)
  UserAssignment.create!(assignable: e2, user: user, user_role: role, team: team) rescue nil

  p3 = Project.create!(name: 'HDAC Inhibitor Screening', team: team, created_by: user)
  UserAssignment.create!(assignable: p3, user: user, user_role: role, team: team) rescue nil
  e3 = Experiment.create!(name: 'Toxicity Screening 2024', project: p3, created_by: user, last_modified_by: user)
  UserAssignment.create!(assignable: e3, user: user, user_role: role, team: team) rescue nil

  t3 = MyModule.create!(name: 'Cell Viability Assay', experiment: e3, created_by: user)
  UserAssignment.create!(assignable: t3, user: user, user_role: role, team: team) rescue nil

  rt = ResultText.create!(text: '<p>Vorinostat showed significant toxicity at 10uM.</p>')
  Result.create!(name: 'Assay Notes', my_module: t3, result_type: 'ResultText', result_specific_id: rt.id) rescue nil
  
  puts "SUCCESS: Ruby data creation completed"
rescue => e
  puts "ERROR: #{e.message}"
end
EOF

OUTPUT=$(scinote_rails_query "$(cat /tmp/setup_search_data.rb)")
echo "$OUTPUT"

# Fallback to direct SQL if Rails Runner fails
if ! echo "$OUTPUT" | grep -q "SUCCESS"; then
    echo "Ruby script failed, falling back to direct SQL inserts..."
    
    P1_ID=$(scinote_db_query "INSERT INTO projects (name, visibility, team_id, created_by_id, created_at, updated_at, archived, demo, due_date_notification_sent) VALUES ('Cutaneous T-Cell Lymphoma', 1, 1, 1, NOW(), NOW(), false, false, false) RETURNING id;" | tr -d '[:space:]')
    ensure_user_assignment "Project" "$P1_ID"
    E1_ID=$(scinote_db_query "INSERT INTO experiments (name, project_id, created_by_id, last_modified_by_id, archived, due_date_notification_sent, created_at, updated_at, uuid) VALUES ('Vorinostat Efficacy Study VR-01', $P1_ID, 1, 1, false, false, NOW(), NOW(), gen_random_uuid()) RETURNING id;" | tr -d '[:space:]')
    ensure_user_assignment "Experiment" "$E1_ID"

    P2_ID=$(scinote_db_query "INSERT INTO projects (name, visibility, team_id, created_by_id, created_at, updated_at, archived, demo, due_date_notification_sent) VALUES ('Phase I Safety Trials', 1, 1, 1, NOW(), NOW(), false, false, false) RETURNING id;" | tr -d '[:space:]')
    ensure_user_assignment "Project" "$P2_ID"
    E2_ID=$(scinote_db_query "INSERT INTO experiments (name, description, project_id, created_by_id, last_modified_by_id, archived, due_date_notification_sent, created_at, updated_at, uuid) VALUES ('PK Profile - Group 4', '<p>Testing PK profile of Vorinostat in Group 4</p>', $P2_ID, 1, 1, false, false, NOW(), NOW(), gen_random_uuid()) RETURNING id;" | tr -d '[:space:]')
    ensure_user_assignment "Experiment" "$E2_ID"

    P3_ID=$(scinote_db_query "INSERT INTO projects (name, visibility, team_id, created_by_id, created_at, updated_at, archived, demo, due_date_notification_sent) VALUES ('HDAC Inhibitor Screening', 1, 1, 1, NOW(), NOW(), false, false, false) RETURNING id;" | tr -d '[:space:]')
    ensure_user_assignment "Project" "$P3_ID"
    E3_ID=$(scinote_db_query "INSERT INTO experiments (name, project_id, created_by_id, last_modified_by_id, archived, due_date_notification_sent, created_at, updated_at, uuid) VALUES ('Toxicity Screening 2024', $P3_ID, 1, 1, false, false, NOW(), NOW(), gen_random_uuid()) RETURNING id;" | tr -d '[:space:]')
    ensure_user_assignment "Experiment" "$E3_ID"

    T3_ID=$(scinote_db_query "INSERT INTO my_modules (name, experiment_id, created_at, updated_at, archived, workflow_order, created_by_id) VALUES ('Cell Viability Assay', $E3_ID, NOW(), NOW(), false, 0, 1) RETURNING id;" | tr -d '[:space:]')
    ensure_user_assignment "MyModule" "$T3_ID"

    R3_ID=$(scinote_db_query "INSERT INTO results (my_module_id, name, created_at, updated_at, result_type) VALUES ($T3_ID, 'Assay Notes', NOW(), NOW(), 'ResultText') RETURNING id;" | tr -d '[:space:]')
    scinote_db_query "INSERT INTO result_texts (result_id, text, created_at, updated_at) VALUES ($R3_ID, '<p>Vorinostat showed significant toxicity at 10uM.</p>', NOW(), NOW());"

    # Attempt to trigger search index rebuild if multisearch is used
    docker exec scinote_web bash -c "bundle exec rake pg_search:multisearch:rebuild[Project] 2>/dev/null || true"
    docker exec scinote_web bash -c "bundle exec rake pg_search:multisearch:rebuild[Experiment] 2>/dev/null || true"
    docker exec scinote_web bash -c "bundle exec rake pg_search:multisearch:rebuild[MyModule] 2>/dev/null || true"
    docker exec scinote_web bash -c "bundle exec rake pg_search:multisearch:rebuild[ResultText] 2>/dev/null || true"
fi

# Ensure Firefox is running at the login page
ensure_firefox_running "${SCINOTE_URL}/users/sign_in"

sleep 3
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="