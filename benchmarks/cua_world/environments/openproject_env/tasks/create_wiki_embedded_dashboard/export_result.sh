#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting task results ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Extract Wiki page content and Status IDs using Rails runner
# We need to find the specific page and its content
# We also need the ID of 'In progress' to verify the macro filter
ruby_script="
  require 'json'
  
  res = {
    page_found: false,
    page_title: '',
    content_text: '',
    status_id_in_progress: nil,
    project_found: false
  }

  begin
    # Get Project
    proj = Project.find_by(identifier: 'devops-automation')
    if proj
      res[:project_found] = true
      
      # Find Wiki Page
      # Note: Wiki pages are stored in 'wiki_pages' table, linked to 'wikis' table
      wiki = proj.wiki
      if wiki
        page = wiki.find_page('Live Incident Board')
        if page
          res[:page_found] = true
          res[:page_title] = page.title
          # The content is in the associated content record
          if page.content
            res[:content_text] = page.content.text
          end
        end
      end
    end

    # Get Status ID for 'In progress' to help verifier check the macro
    status = Status.find_by(name: 'In progress')
    res[:status_id_in_progress] = status ? status.id : nil

  rescue => e
    res[:error] = e.message
  end

  puts 'JSON_START' + res.to_json + 'JSON_END'
"

echo "Running Rails extraction script..."
# Run the ruby script inside the container
raw_output=$(op_rails "$ruby_script")

# Extract the JSON part
json_output=$(echo "$raw_output" | sed -n 's/.*JSON_START\(.*\)JSON_END.*/\1/p')

# Save to result file
if [ -n "$json_output" ]; then
    echo "$json_output" > /tmp/task_result.json
else
    echo "{\"error\": \"Failed to extract data from Rails runner\"}" > /tmp/task_result.json
fi

# Add timestamp info
# (We append this by reading the json, adding fields, and writing back, or just rely on verifier to check file timestamps if needed.
# Here we'll just leave the rails output as the primary source of truth.)

echo "Export complete. Result:"
cat /tmp/task_result.json