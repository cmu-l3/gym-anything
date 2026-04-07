#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# We use a Ruby script inside the container to verify the state of the work package.
# This ensures we check the database directly for:
# 1. Status and Progress
# 2. Time entries (specifically created by alice.johnson TODAY)
# 3. Comments (specifically created by alice.johnson TODAY)

RUBY_SCRIPT=$(cat <<EOF
require 'json'
require 'date'

begin
  # Find the specific work package
  wp = WorkPackage.joins(:project)
                  .where(projects: { identifier: 'ecommerce-platform' })
                  .where("subject LIKE ?", "%Implement product search with Elasticsearch%")
                  .first

  unless wp
    puts JSON.generate({ error: "Work package not found" })
    exit
  end

  # Check status and percentage
  status_name = wp.status.name
  done_ratio = wp.done_ratio

  # Check for time entries by alice.johnson on this WP today
  alice = User.find_by(login: 'alice.johnson')
  
  if alice
    # Time entries
    time_entry = TimeEntry.where(work_package_id: wp.id, user_id: alice.id, spent_on: Date.today).last
    hours_logged = time_entry ? time_entry.hours : 0.0
    
    # Comments (Journals)
    # We look for journals created by Alice today that have notes
    journal = Journal.where(journable_type: 'WorkPackage', journable_id: wp.id, user_id: alice.id)
                     .where("created_at > ?", Date.today.to_time)
                     .where.not(notes: [nil, ""])
                     .order(created_at: :desc)
                     .first
    
    last_comment = journal ? journal.notes : nil
    comment_author = journal ? journal.user.login : nil
  else
    hours_logged = 0.0
    last_comment = nil
    comment_author = nil
  end

  result = {
    wp_found: true,
    wp_id: wp.id,
    status: status_name,
    done_ratio: done_ratio,
    hours_logged: hours_logged,
    last_comment: last_comment,
    comment_author: comment_author,
    time_entry_user: (time_entry ? time_entry.user.login : nil),
    debug_info: {
        alice_found: !alice.nil?,
        wp_subject: wp.subject
    }
  }

  puts JSON.generate(result)
rescue => e
  puts JSON.generate({ error: e.message, backtrace: e.backtrace })
end
EOF
)

# Execute the Ruby script in the container
echo "Running verification query..."
RAW_JSON=$(docker exec openproject bash -c "cd /app && bin/rails runner -e production '$RUBY_SCRIPT'" 2>/dev/null)

# Clean up any Rails runner noise (sometimes it outputs deprecation warnings)
# We look for the last line that looks like JSON
JSON_OUTPUT=$(echo "$RAW_JSON" | grep "^{" | tail -n 1)

if [ -z "$JSON_OUTPUT" ]; then
    # Fallback if grep failed
    JSON_OUTPUT="{ \"error\": \"Failed to parse Rails output\", \"raw\": \"$RAW_JSON\" }"
fi

# Write result to file
echo "$JSON_OUTPUT" > /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Exported JSON:"
cat /tmp/task_result.json

echo "=== Export complete ==="