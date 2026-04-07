#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Correct Misfiled Time Entry Task ==="

# Wait for OpenProject to be ready
wait_for_openproject

# Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Create the specific data scenario using Rails runner
# We create the project (if needed), work packages, and the erroneous time entry.
# We output the ID of the created time entry to a file for the verifier to track.

cat > /tmp/setup_scenario.rb << 'RUBY_EOF'
begin
  # Find or create project
  p = Project.find_by(identifier: 'mobile-banking-app')
  unless p
    p = Project.new(name: 'Mobile Banking App', identifier: 'mobile-banking-app')
    p.save!(validate: false)
    p.enabled_module_names = p.enabled_module_names | ['time_tracking', 'costs']
    p.save!
  end

  admin = User.find_by(login: 'admin')
  
  # Ensure target work packages exist
  wp_wrong = WorkPackage.find_or_create_by!(project: p, subject: 'Asset Design') do |w|
    w.author = admin
    w.type = Type.first
    w.status = Status.default
    w.priority = IssuePriority.default
  end
  
  wp_right = WorkPackage.find_or_create_by!(project: p, subject: 'Security Audit') do |w|
    w.author = admin
    w.type = Type.first
    w.status = Status.default
    w.priority = IssuePriority.default
  end

  # Create or reset the erroneous time entry
  # We look for one with the specific comment to avoid cluttering if run multiple times
  te = TimeEntry.find_by(comments: 'External security analysis', project: p)
  
  if te
    # Reset state if it already exists
    te.work_package = wp_wrong
    te.hours = 4.0
    te.spent_on = Date.today
    te.save!
  else
    te = TimeEntry.create!(
      project: p,
      user: admin,
      work_package: wp_wrong,
      hours: 4.0,
      comments: 'External security analysis',
      spent_on: Date.today,
      activity: TimeEntryActivity.first || TimeEntryActivity.new(name: 'Dev', active: true)
    )
  end

  puts "TIME_ENTRY_ID:#{te.id}"
rescue => e
  puts "ERROR: #{e.message}"
  exit 1
end
RUBY_EOF

# Run the ruby script inside the container
echo "Running Rails setup script..."
OUTPUT=$(op_rails "$(cat /tmp/setup_scenario.rb)")
echo "$OUTPUT"

# Extract the ID
TE_ID=$(echo "$OUTPUT" | grep "TIME_ENTRY_ID:" | cut -d':' -f2 | tr -d '[:space:]')

if [ -z "$TE_ID" ]; then
    echo "Failed to set up time entry. Output:"
    echo "$OUTPUT"
    exit 1
fi

echo "$TE_ID" > /tmp/target_time_entry_id.txt
echo "Target Time Entry ID: $TE_ID"

# Launch Firefox to the project's time entries or cost reports to make it slightly challenging but accessible
# Or just the project overview. Let's go to the project overview.
launch_firefox_to "http://localhost:8080/projects/mobile-banking-app" 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="