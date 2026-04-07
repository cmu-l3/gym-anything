#!/bin/bash
set -e
echo "=== Exporting create_meeting_with_minutes results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Extract Data via Rails Runner
# We run a comprehensive Ruby script inside the container to gather all meeting details.
# This avoids making multiple slow calls and handles the complex object graph (Meeting -> Agenda -> Notes).

RUBY_SCRIPT=$(cat << 'RUBY_EOF'
require 'json'

def normalize(str)
  str.to_s.downcase.strip
end

result = {
  found: false,
  metadata: {},
  agenda: [],
  participants: [],
  notes_text: "",
  created_at_ts: 0
}

begin
  p = Project.find_by(identifier: 'ecommerce-platform')
  target = nil
  
  # Find the most recently created meeting that matches the title
  # This handles cases where the agent might create multiple attempts
  candidates = Meeting.where(project: p).order(created_at: :desc)
  
  candidates.each do |m|
    if normalize(m.title).include?('sprint 1 retrospective')
      target = m
      break
    end
  end

  if target
    result[:found] = true
    result[:created_at_ts] = target.created_at.to_i
    
    # Metadata
    result[:metadata] = {
      title: target.title.to_s,
      location: target.location.to_s,
      start_time: target.start_time.to_s, # ISO format
      duration: target.duration.to_f,
      project_id: target.project_id,
      meeting_id: target.id
    }

    # Agenda Items (Handle both structured agenda and legacy text fields if present)
    if target.respond_to?(:agenda_items)
      target.agenda_items.order(:position).each do |ai|
        result[:agenda] << {
          title: ai.title.to_s,
          notes: ai.notes.to_s
        }
      end
    end

    # Participants
    if target.respond_to?(:participants)
      target.participants.each do |mp|
        uname = mp.user ? mp.user.name.to_s : "unknown"
        result[:participants] << {
          name: uname,
          invited: mp.invited,
          attended: mp.attended
        }
      end
    end

    # Consolidated Notes Text for searching
    # (Combine agenda item notes and classic minutes text)
    full_text = ""
    
    # Add structured agenda notes
    result[:agenda].each { |ai| full_text += " " + ai[:notes] }
    
    # Add classic minutes if present
    if target.respond_to?(:minutes) && target.minutes
      full_text += " " + target.minutes.text.to_s
    end
    
    # Add classic agenda text if present
    if target.respond_to?(:agenda) && target.agenda
      full_text += " " + target.agenda.text.to_s
    end
    
    result[:notes_text] = full_text
  end

rescue => e
  result[:error] = e.message
end

puts "__JSON_START__"
puts JSON.generate(result)
puts "__JSON_END__"
RUBY_EOF
)

# Run the Ruby script in the container
raw_output=$(docker exec openproject bash -c "cd /app && bin/rails runner -e production \"$RUBY_SCRIPT\"" 2>/dev/null || echo "Error running rails runner")

# Extract the JSON part
json_output=$(echo "$raw_output" | sed -n '/__JSON_START__/,/__JSON_END__/p' | grep -v "__JSON_" || echo "{}")

# Validate JSON before saving
if echo "$json_output" | jq . >/dev/null 2>&1; then
    echo "$json_output" > /tmp/task_result.json
else
    echo "ERROR: Failed to generate valid JSON result"
    echo "Raw output: $raw_output"
    echo '{"found": false, "error": "JSON generation failed"}' > /tmp/task_result.json
fi

# Add task timing info to result
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_meeting_count.txt 2>/dev/null || echo "0")

# Use jq to merge timing info (safe atomic update)
jq --arg start "$TASK_START" --arg init_count "$INITIAL_COUNT" \
   '. + {task_start_timestamp: $start, initial_meeting_count: $init_count}' \
   /tmp/task_result.json > /tmp/task_result.tmp && mv /tmp/task_result.tmp /tmp/task_result.json

# Set permissions for the verifier to read
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="