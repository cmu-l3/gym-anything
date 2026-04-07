#!/bin/bash
set -euo pipefail
echo "=== Exporting bulk_edit_time_entries results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Copy seed info back to container to use in rails runner script
docker cp /tmp/seed_data_info.json redmine:/tmp/seed_data_info.json

# Execute verification query inside Redmine container
# We verify:
# 1. State of Target IDs (should be Development)
# 2. State of Distractor IDs (should be Design)
# 3. Count of remaining 'Design' entries for junior_dev
docker exec -e RAILS_ENV=production redmine bundle exec rails runner '
  require "json"
  
  seed_info = JSON.parse(File.read("/tmp/seed_data_info.json"))
  target_ids = seed_info["target_ids"]
  distractor_ids = seed_info["distractor_ids"]

  # Check Targets
  targets = TimeEntry.where(id: target_ids).map do |t|
    {
      "id" => t.id,
      "activity_name" => t.activity.name,
      "hours" => t.hours.to_f,
      "user_login" => t.user.login
    }
  end

  # Check Distractors
  distractors = TimeEntry.where(id: distractor_ids).map do |t|
    {
      "id" => t.id,
      "activity_name" => t.activity.name,
      "hours" => t.hours.to_f,
      "user_login" => t.user.login
    }
  end

  # Check remaining "Design" entries for junior_dev in this project
  jr_dev = User.find_by(login: "junior_dev")
  design_act = TimeEntryActivity.find_by(name: "Design")
  remaining_mistakes = TimeEntry.where(user: jr_dev, activity: design_act).count

  result = {
    "targets" => targets,
    "distractors" => distractors,
    "remaining_mistakes" => remaining_mistakes,
    "timestamp" => Time.now.to_i
  }

  File.write("/tmp/verification_result.json", result.to_json)
'

# Copy result out
rm -f /tmp/task_result.json 2>/dev/null || true
docker cp redmine:/tmp/verification_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="