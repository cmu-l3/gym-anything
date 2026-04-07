#!/bin/bash
# Task setup: bulk_tag_work_packages
# 1. Ensures OpenProject is running.
# 2. Injects specific 'Search' related work packages to ensure a robust test set.
# 3. Launches Firefox to the project's work package list.

source /workspace/scripts/task_utils.sh

echo "=== Setting up bulk_tag_work_packages task ==="

# 1. Wait for OpenProject to be ready
wait_for_openproject

# 2. Inject Data via Rails Runner
# We need to ensure there are specific work packages to find, and that they don't already have the tag.
echo "Injecting task data..."

cat > /tmp/inject_search_data.rb << 'RUBY_EOF'
project = Project.find_by(identifier: 'ecommerce-platform')
unless project
  puts "Project not found!"
  exit 1
end

admin = User.find_by(login: 'admin')

# Define tasks to ensure exist
tasks = [
  "Refine search result relevance ranking",
  "Add autocomplete to search bar",
  "Fix search filters on mobile view",
  "Investigate slow search queries"
]

tasks.each do |subject|
  # Check if exists to avoid duplicates
  wp = project.work_packages.find_by(subject: subject)
  unless wp
    wp = WorkPackage.new(
      project: project,
      subject: subject,
      type: project.types.first,
      status: Status.default,
      priority: IssuePriority.default,
      author: admin
    )
    wp.save!(validate: false)
    puts "Created WP: #{subject}"
  else
    # Ensure tag is NOT present at start
    if wp.tags.any? { |t| t.name == 'search-initiative' }
      wp.tags = wp.tags.reject { |t| t.name == 'search-initiative' }
      wp.save!(validate: false)
      puts "Removed pre-existing tag from: #{subject}"
    end
  end
end
RUBY_EOF

# Execute the injection script inside the container
op_rails "$(cat /tmp/inject_search_data.rb)"

# 3. Setup Browser
# Navigate to the work packages list for the project
launch_firefox_to "http://localhost:8080/projects/ecommerce-platform/work_packages" 5

# 4. Record Initial State
# Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete: bulk_tag_work_packages ==="