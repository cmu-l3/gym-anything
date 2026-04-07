#!/bin/bash
echo "=== Setting up configure_inventory_alerts task ==="

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Clean up any previous task files
rm -f /tmp/configure_inventory_alerts_result.json 2>/dev/null || true

echo "=== Seeding inventory via Rails Runner ==="
# We use Rails runner because SciNote's inventory uses a complex Entity-Attribute-Value (EAV) structure
# that is difficult to reliably seed with raw SQL across different versions.
cat > /tmp/setup_inventory.rb << 'EOF'
begin
  # Find or create Team & User
  team = Team.first || Team.new(name: 'Default')
  user = User.find_by(email: 'admin@scinote.net') || User.first
  
  # Create Repository (Inventory)
  repo = Repository.find_or_create_by!(name: 'PCR Reagents', team: team) do |r|
    r.created_by = user if r.respond_to?(:created_by=)
  end
  
  # Create Items (Repository Rows)
  row1 = RepositoryRow.find_or_create_by!(name: 'Taq DNA Polymerase', repository: repo) do |r|
    r.created_by = user if r.respond_to?(:created_by=)
  end
  
  row2 = RepositoryRow.find_or_create_by!(name: 'dNTP Mix 10mM', repository: repo) do |r|
    r.created_by = user if r.respond_to?(:created_by=)
  end
  
  puts "Inventory setup complete. Repo: #{repo.id}, Rows: #{row1.id}, #{row2.id}"
rescue => e
  puts "Error setting up inventory: #{e.message}"
end
EOF

# Execute the Ruby script inside the SciNote web container
docker exec scinote_web bash -c "bundle exec rails runner /tmp/setup_inventory.rb"

# Ensure Firefox is running at the correct page
ensure_firefox_running "${SCINOTE_URL}/users/sign_in"

# Take initial screenshot of the starting state
sleep 3
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="