#!/bin/bash
# Export results for release_management_pipeline task
# Queries OpenProject database via Rails runner to extract ground-truth state.

echo "=== Exporting release_management_pipeline result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_STATUS_COUNT=$(cat /tmp/rmp_initial_status_count 2>/dev/null || echo "0")
INITIAL_PROJECT_COUNT=$(cat /tmp/rmp_initial_project_count 2>/dev/null || echo "0")

# Write a single Ruby script that outputs all data as one JSON blob
cat > /tmp/rmp_verify.rb << 'RUBYEOF'
require 'json'

result = {}

# 1. Check statuses
result['statuses'] = { 'found' => Status.where(name: ["Ready for QA", "QA Passed", "Staging Deployed"]).pluck(:name) }

# 2. Check workflow transitions for Member + Feature
dev = Role.find_by(name: "Member")
feat = Type.find_by(name: "Feature")
transitions = []
if dev && feat
  status_map = Status.all.pluck(:id, :name).to_h
  Workflow.where(role_id: dev.id, type_id: feat.id).pluck(:old_status_id, :new_status_id).each do |pair|
    transitions << [status_map[pair[0]], status_map[pair[1]]]
  end
end
result['workflow'] = { 'transitions' => transitions }

# 3. Check custom field
cf = CustomField.find_by(name: "Target Release", type: "WorkPackageCustomField")
if cf
  result['custom_field'] = {
    'exists' => true,
    'format' => cf.field_format,
    'values' => cf.custom_options.order(:position).pluck(:value),
    'project_ids' => cf.projects.pluck(:identifier),
    'type_names' => cf.types.pluck(:name)
  }
else
  result['custom_field'] = { 'exists' => false }
end

# 4. Check project
p = Project.find_by(identifier: "release-coordination")
if p
  result['project'] = {
    'exists' => true,
    'name' => p.name,
    'identifier' => p.identifier,
    'is_public' => p.public?,
    'modules' => p.enabled_module_names
  }

  # 5. Check members
  members = []
  p.members.includes(:principal, :roles).each do |m|
    members << { 'login' => m.principal&.login, 'roles' => m.roles.pluck(:name) }
  end
  result['members'] = { 'members' => members }

  # 6. Check work packages
  wps = []
  p.work_packages.includes(:type, :assigned_to, :status).each do |wp|
    cf_val = nil
    if cf
      cv = wp.custom_value_for(cf)
      if cv && cv.value.present?
        opt = cf.custom_options.find_by(id: cv.value)
        cf_val = opt ? opt.value : cv.value
      end
    end
    wps << {
      'subject' => wp.subject,
      'type_name' => wp.type&.name,
      'assignee' => wp.assigned_to&.login,
      'status' => wp.status&.name,
      'target_release' => cf_val
    }
  end
  result['work_packages'] = { 'work_packages' => wps }

  # 7. Check boards
  boards = []
  begin
    Grids::Grid.where(project: p).each do |g|
      if g.type.to_s.include?("Board")
        boards << {
          'name' => g.name,
          'column_count' => g.widgets.count,
          'board_type' => (g.options || {})["type"],
          'board_attribute' => (g.options || {})["attribute"]
        }
      end
    end
  rescue => e
    # Grids module may not be available
  end
  result['boards'] = { 'boards' => boards }

  # 8. Check wiki
  if p.wiki
    page = p.wiki.pages.find_by(title: "Release Management Process")
    if page
      ct = page.respond_to?(:text) ? page.text.to_s : (page.content ? page.content.text.to_s : "")
      result['wiki'] = {
        'exists' => true,
        'title' => page.title,
        'content_length' => ct.length,
        'content_lower' => ct.downcase[0..2000]
      }
    else
      result['wiki'] = { 'exists' => false }
    end
  else
    result['wiki'] = { 'exists' => false }
  end
else
  result['project'] = { 'exists' => false }
  result['members'] = { 'members' => [] }
  result['work_packages'] = { 'work_packages' => [] }
  result['boards'] = { 'boards' => [] }
  result['wiki'] = { 'exists' => false }
end

puts result.to_json
RUBYEOF

# Copy Ruby script into the container and execute it
docker cp /tmp/rmp_verify.rb openproject:/tmp/rmp_verify.rb 2>/dev/null
RAILS_OUTPUT=$(docker exec openproject bash -c "cd /app && bundle exec rails runner /tmp/rmp_verify.rb 2>/dev/null" 2>/dev/null)

# Extract JSON from Rails output (may contain INFO log lines before the JSON)
RAILS_JSON=$(echo "$RAILS_OUTPUT" | grep -o '{.*}' | tail -n 1)

if [ -z "$RAILS_JSON" ]; then
    echo "WARNING: No JSON from Rails runner. Raw output:"
    echo "$RAILS_OUTPUT"
    RAILS_JSON='{"statuses":{"found":[]},"workflow":{"transitions":[]},"custom_field":{"exists":false},"project":{"exists":false},"members":{"members":[]},"work_packages":{"work_packages":[]},"boards":{"boards":[]},"wiki":{"exists":false}}'
fi

# Assemble final result with baselines
python3 -c "
import json, sys

try:
    rails_data = json.loads('''$RAILS_JSON''')
except:
    rails_data = {}

result = rails_data
result['task_start'] = $TASK_START
result['initial_status_count'] = $INITIAL_STATUS_COUNT
result['initial_project_count'] = $INITIAL_PROJECT_COUNT

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
"

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete: release_management_pipeline ==="
