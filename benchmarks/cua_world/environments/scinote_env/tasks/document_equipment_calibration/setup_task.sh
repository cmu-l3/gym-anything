#!/bin/bash
set -e
echo "=== Setting up Document Equipment Calibration task ==="

source /workspace/scripts/task_utils.sh

# Ensure SciNote is fully running
ensure_docker_healthy
wait_for_scinote_ready 90

# Get container time for exact matching (prevents host/container timezone drift issues)
CONTAINER_START=$(docker exec scinote_web date +%s)
echo "$CONTAINER_START" > /tmp/task_start_time.txt

echo "Seeding database with Laboratory Equipment..."

# Seed script using Rails Runner for reliable EAV architecture manipulation
cat << 'EOF' > /tmp/seed_eq.rb
begin
  user = User.find_by(email: 'admin@scinote.net') || User.first
  team = Team.first
  repo = Repository.find_or_create_by!(name: 'Laboratory Equipment', team: team)
  repo.update(created_by: user)

  # Clear existing to ensure clean state
  repo.repository_rows.destroy_all

  c_serial = repo.repository_columns.find_or_create_by!(name: 'Serial Number')
  c_status = repo.repository_columns.find_or_create_by!(name: 'Status')
  c_last = repo.repository_columns.find_or_create_by!(name: 'Last Calibration')
  c_next = repo.repository_columns.find_or_create_by!(name: 'Next Calibration')
  c_notes = repo.repository_columns.find_or_create_by!(name: 'Maintenance Notes')

  # Ensure they are treated as text/string columns so agent can type directly
  [c_serial, c_status, c_last, c_next, c_notes].each { |c| c.update_column(:data_type, 1) rescue nil }

  def mk_row(repo, user, cols, name, serial, status, last_cal, next_cal, notes)
    row = repo.repository_rows.create!(name: name, created_by: user)
    row.repository_cells.create!(repository_column: cols[0], value_text: serial)
    row.repository_cells.create!(repository_column: cols[1], value_text: status)
    row.repository_cells.create!(repository_column: cols[2], value_text: last_cal)
    row.repository_cells.create!(repository_column: cols[3], value_text: next_cal)
    row.repository_cells.create!(repository_column: cols[4], value_text: notes)
  end

  cols = [c_serial, c_status, c_last, c_next, c_notes]

  mk_row(repo, user, cols, 'Mettler Toledo pH Meter', 'MT-PH-001', 'Due for Cal', 30.days.ago.to_date.to_s, Date.today.to_s, 'Previous cal ok')
  mk_row(repo, user, cols, 'Eppendorf Centrifuge 5424', 'EP-CEN-992', 'Operational', 10.days.ago.to_date.to_s, 20.days.from_now.to_date.to_s, 'Rotor balanced')

  puts "Seed OK"
rescue => e
  puts "Error: #{e.message}"
end
EOF

docker exec scinote_web bash -c "bundle exec rails runner /tmp/seed_eq.rb"

# Start Firefox and navigate directly to inventories
ensure_firefox_running "${SCINOTE_URL}/inventories"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="