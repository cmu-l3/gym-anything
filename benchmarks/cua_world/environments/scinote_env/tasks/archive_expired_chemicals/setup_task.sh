#!/bin/bash
set -e
echo "=== Setting up archive_expired_chemicals task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure SciNote containers are running
ensure_docker_healthy
wait_for_scinote_ready 60

echo "=== Seeding inventory data ==="

# Create a Ruby script to safely seed the database using Rails models
cat << 'RUBYEOF' > /tmp/seed_inventory.rb
begin
  user = User.find_by(email: 'admin@scinote.net')
  team = Team.first || user.teams.first
  
  # Clean up any existing repository with this name to ensure clean state
  repo = Repository.find_by(name: 'Chemical Storage', team_id: team.id)
  if repo
    repo.destroy 
    puts "Cleaned up existing repository."
  end
  
  # Create new repository
  repo = Repository.create!(name: 'Chemical Storage', team: team, created_by: user)
  puts "Created repository: Chemical Storage"
  
  # Define items with explicit dates in the name for robust schema-independent parsing
  items = [
    { name: 'Acetonitrile (Grade A) | Expiry Date: 2022-05-20' },
    { name: 'Methanol (HPLC) | Expiry Date: 2023-11-10' },
    { name: 'Ethanol 96% | Expiry Date: 2027-01-15' },
    { name: 'Chloroform | Expiry Date: 2021-08-30' },
    { name: 'Isopropanol | Expiry Date: 2026-05-05' }
  ]
  
  items.each do |item|
    RepositoryRow.create!(name: item[:name], repository: repo, team: team, created_by: user)
    puts "Created item: #{item[:name]}"
  end
  
  puts "Seed completed successfully."
rescue => e
  puts "Error during seed: #{e.message}"
  exit 1
end
RUBYEOF

# Execute the Ruby script securely inside the container
docker cp /tmp/seed_inventory.rb scinote_web:/tmp/seed_inventory.rb
docker exec scinote_web bundle exec rails runner /tmp/seed_inventory.rb

# Start Firefox and ensure it's logged in or at the sign-in page
ensure_firefox_running "${SCINOTE_URL}/users/sign_in"

# Let UI stabilize and capture screenshot
sleep 3
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="