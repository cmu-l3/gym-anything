#!/bin/bash
set -e
echo "=== Setting up set_work_package_hierarchy task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# 2. Wait for OpenProject to be ready
wait_for_openproject

# 3. Clean and Prepare Data (Ruby script via Rails Runner)
# - Ensures target WPs exist
# - Resets their parent_id to nil (flat hierarchy)
# - Deletes any pre-existing Epics with the target names
echo "Preparing seed data..."

PREP_RUBY='
  require "json"
  project = Project.find_by(identifier: "ecommerce-platform")
  
  if project.nil?
    puts "ERROR: Project not found"
    exit 1
  end

  # Define targets that must exist
  targets = [
    "Implement product search with Elasticsearch",
    "Implement product recommendation engine",
    "Design new product page layout",
    "Fix broken checkout on mobile Safari"
  ]

  # Reset parents for targets
  targets.each do |subj|
    wp = WorkPackage.where(project: project).where("subject LIKE ?", "%#{subj}%").first
    if wp
      if wp.parent_id.present?
        wp.parent_id = nil
        wp.save!(validate: false)
        puts "Reset parent for: #{subj}"
      end
    else
      puts "WARNING: Target WP not found: #{subj}"
    end
  end

  # Delete pre-existing epics to ensure clean slate
  ["Search & Discovery Epic", "Checkout & Payments Epic"].each do |name|
    WorkPackage.where(project: project, subject: name).destroy_all
    puts "Cleaned old epic: #{name}"
  end
'

# Run the preparation script inside the container
docker exec openproject bash -lc "cd /app && bin/rails runner -e production '$PREP_RUBY'"

# 4. Launch Firefox
echo "Launching Firefox..."
PROJECT_ID=$(get_project_id "ecommerce-platform")
URL="http://localhost:8080/projects/ecommerce-platform/work_packages"

launch_firefox_to "$URL" 10
maximize_firefox

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="