#!/bin/bash
echo "=== Exporting digitize_legacy_entry result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# 1. Export ground truth mapping
cp /tmp/ground_truth.json /tmp/export_ground_truth.json 2>/dev/null || echo "{}" > /tmp/export_ground_truth.json

# 2. Use Rails to extract tasks, comments, and attachments securely via global models
scinote_rails_query "
project = Project.find_by(name: 'Legacy Archive')
tasks = []
if project
  project.experiments.each do |e|
    e.my_modules.each do |mm|
      atts = []
      begin
        atts = ActiveStorage::Attachment.where(record_type: 'MyModule', record_id: mm.id).map{|a| a.blob.filename.to_s}
      rescue
      end
      
      comms = []
      begin
        comms = Comment.where(commentable_type: 'MyModule', commentable_id: mm.id).map(&:message)
      rescue
      end
      
      desc = mm.description || ''
      
      tasks << {
        id: mm.id,
        name: mm.name,
        description: desc,
        attachments: atts,
        comments: comms,
        created_at: mm.created_at
      }
    end
  end
end
require 'json'
File.write('/tmp/rails_export.json', tasks.to_json)
"

# 3. Read it out of docker container
if docker exec scinote_web stat /tmp/rails_export.json >/dev/null 2>&1; then
    docker exec scinote_web cat /tmp/rails_export.json > /tmp/export_tasks.json
else
    echo "[]" > /tmp/export_tasks.json
fi

# 4. Combine into final JSON payload
cat > /tmp/digitize_result.json <<EOF
{
  "ground_truth": $(cat /tmp/export_ground_truth.json),
  "tasks": $(cat /tmp/export_tasks.json)
}
EOF

chmod 666 /tmp/digitize_result.json
echo "Result successfully exported to /tmp/digitize_result.json"
echo "=== Export complete ==="