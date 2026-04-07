#!/bin/bash
echo "=== Setting up identify_and_list_low_stock_items task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Generate a robust Ruby script to seed the database
cat > /tmp/seed_data.rb << 'RUBYEOF'
begin
  team = Team.first
  user = User.find_by(email: 'admin@scinote.net') || User.first
  owner_role = UserRole.find_by(name: 'Owner', predefined: true) || UserRole.first

  # 1. Setup Project
  project = Project.find_or_create_by!(name: 'Lab Administration', team: team) do |p|
    p.created_by = user
    p.visibility = 1
  end
  UserAssignment.find_or_create_by!(assignable: project, user: user) do |ua|
    ua.user_role = owner_role
    ua.team = team
  end

  # 2. Setup Experiment
  experiment = Experiment.find_or_create_by!(name: 'Purchasing', project: project) do |e|
    e.created_by = user
  end
  UserAssignment.find_or_create_by!(assignable: experiment, user: user) do |ua|
    ua.user_role = owner_role
    ua.team = team
  end

  # 3. Setup Inventory Repository
  repo = Repository.find_or_create_by!(name: 'General Chemicals', team: team) do |r|
    r.created_by = user
  end

  # Ensure a clean slate for the inventory
  repo.repository_rows.destroy_all

  # 4. Insert Inventory Items with amounts visible in their names
  items = [
    "Acetone (4 L)", 
    "Methanol (3 L)", 
    "DMSO (8 L)", 
    "Hexane (2 L)",
    "Ethanol (50 L)", 
    "PBS Buffer (100 L)", 
    "Chloroform (25 L)", 
    "Dichloromethane (15 L)",
    "Toluene (12 L)", 
    "Deionized Water (500 L)", 
    "Isopropanol (20 L)", 
    "Ethyl Acetate (40 L)"
  ]

  items.each do |item_name|
    RepositoryRow.create!(name: item_name, repository: repo, created_by: user)
  end
  
  puts "Seed data successfully populated."
rescue => e
  puts "Error during seed data generation: #{e.message}"
end
RUBYEOF

# Copy the Ruby script into the docker container and run it
docker cp /tmp/seed_data.rb scinote_web:/tmp/seed_data.rb
docker exec scinote_web bash -c "bundle exec rails runner /tmp/seed_data.rb"

# Ensure Firefox is running and at the login screen
ensure_firefox_running "${SCINOTE_URL}/users/sign_in"

sleep 3
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="