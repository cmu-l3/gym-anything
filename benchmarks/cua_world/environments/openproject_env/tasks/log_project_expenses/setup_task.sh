#!/bin/bash
set -e
echo "=== Setting up log_project_expenses task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure OpenProject is up
wait_for_openproject

# 2. Run Rails setup script to create Project, WP, and Cost Type
#    but explicitly DISABLE the Costs module initially.
cat > /tmp/setup_costs_task.rb << 'RUBY'
require 'json'
begin
  # Create Cost Type
  ct_name = "Site Visit Flat Rate"
  ct = CostType.find_by(name: ct_name)
  if ct.nil?
    ct = CostType.create!(name: ct_name, unit: "Visit", unit_plural: "Visits", fixed: true)
    puts "Created CostType: #{ct.name}"
  end
  
  # Set Rate (valid from yesterday)
  if CostRate.where(cost_type_id: ct.id).empty?
    CostRate.create!(cost_type: ct, rate: 250.00, valid_from: Date.today - 365)
    puts "Created CostRate for #{ct.name}"
  end

  # Create Project
  p_name = "Solar Energy Installation"
  project = Project.find_by(name: p_name)
  if project.nil?
    project = Project.create!(
      name: p_name, 
      identifier: "solar-energy-installation", 
      description: "Residential solar panel installation project."
    )
    puts "Created Project: #{project.name}"
  else
    # Reset modules if it existed
    project.enabled_module_names = ["work_package_tracking", "wiki", "timelines"]
    project.save!
  end

  # Create User (Solar Manager) if needed, or just use admin. 
  # We'll rely on the default 'admin' or 'ga' user being able to see this.
  
  # Disable Costs module initially (to test if agent enables it)
  # Keep basic modules
  project.enabled_module_names = ["work_package_tracking", "wiki", "timelines"]
  project.save!
  puts "Disabled Costs module for #{project.name}"

  # Create Work Package
  wp_subject = "Initial Site Survey - Residential"
  wp = WorkPackage.find_by(project: project, subject: wp_subject)
  if wp.nil?
    wp = WorkPackage.create!(
      project: project,
      subject: wp_subject,
      type: Type.find_by(name: 'Task') || Type.first,
      status: Status.default,
      author: User.find_by(login: 'admin') || User.first,
      priority: IssuePriority.default
    )
    puts "Created Work Package: #{wp.subject}"
  else
    # Clear any existing cost entries on this WP to ensure clean slate
    CostEntry.where(work_package_id: wp.id).destroy_all
    puts "Cleared existing cost entries for WP"
  end

  # Output IDs for verification later
  File.write("/tmp/task_data.json", {
    project_id: project.id,
    wp_id: wp.id,
    cost_type_id: ct.id,
    cost_type_name: ct.name
  }.to_json)

rescue => e
  puts "Error in Ruby setup: #{e.message}"
  puts e.backtrace
  exit 1
end
RUBY

# Run the ruby script inside the container
op_rails "$(cat /tmp/setup_costs_task.rb)"

# 3. Launch Firefox to the project overview
launch_firefox_to "http://localhost:8080/projects/solar-energy-installation" 10

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="