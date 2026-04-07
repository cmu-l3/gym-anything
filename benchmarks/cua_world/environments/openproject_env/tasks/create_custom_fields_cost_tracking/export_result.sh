#!/bin/bash
# Export script for create_custom_fields_cost_tracking task
# Extracts custom field configuration and work package values via Rails runner

set -e
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create a Ruby script to inspect the state
cat > /tmp/inspect_state.rb << 'RUBY_EOF'
require 'json'

result = {
  timestamp: Time.now.to_i,
  custom_fields: {},
  work_packages: []
}

begin
  # 1. Inspect Custom Fields
  ['Cost Category', 'Estimated Budget (USD)'].each do |name|
    cf = CustomField.where(name: name).first
    if cf
      options = []
      if cf.field_format == 'list'
        options = cf.custom_options.order(:position).map(&:value)
      end
      
      # Check project mapping
      # OpenProject logic: if is_for_all is true, it applies to all. 
      # Otherwise check if project is in cf.projects
      is_global = cf.is_for_all?
      project_ids = cf.projects.map(&:identifier)
      
      result[:custom_fields][name] = {
        exists: true,
        id: cf.id,
        format: cf.field_format,
        options: options,
        is_global: is_global,
        project_identifiers: project_ids
      }
    else
      result[:custom_fields][name] = { exists: false }
    end
  end
  
  # 2. Inspect Work Packages
  # We look for specific subjects mentioned in the task
  # Note: Subjects might vary slightly if seeded randomly, but keywords should match
  targets = [
    { key: 'search', keywords: ['product search', 'elasticsearch'] },
    { key: 'checkout', keywords: ['checkout', 'safari'] },
    { key: 'database', keywords: ['database queries', 'category listing'] }
  ]
  
  project = Project.find_by(identifier: 'ecommerce-platform')
  
  if project
    targets.each do |target|
      # Find WP by keywords
      wps = project.work_packages.to_a
      wp = wps.find { |w| target[:keywords].all? { |k| w.subject.downcase.include?(k.downcase) } }
      
      if wp
        wp_data = {
          id: wp.id,
          subject: wp.subject,
          found: true,
          values: {}
        }
        
        # Extract custom values
        result[:custom_fields].each do |cf_name, cf_data|
          next unless cf_data[:exists]
          
          # Custom values are stored in custom_values table
          # We need to resolve the ID for list values
          cv = wp.custom_values.find { |v| v.custom_field_id == cf_data[:id] }
          
          if cv
            val = cv.value
            # If list, resolve option value
            if cf_data[:format] == 'list' && val.present?
              opt = CustomOption.find_by(id: val)
              val = opt ? opt.value : val
            end
            wp_data[:values][cf_name] = val
          else
             wp_data[:values][cf_name] = nil
          end
        end
        
        result[:work_packages] << wp_data
      else
        result[:work_packages] << { found: false, keywords: target[:keywords] }
      end
    end
  end
  
  # 3. Global Count for Anti-Gaming
  result[:total_cf_count] = CustomField.count

rescue => e
  result[:error] = e.message
  result[:backtrace] = e.backtrace
end

puts JSON.generate(result)
RUBY_EOF

# Execute Ruby script inside container
echo "Running inspection script..."
docker exec openproject bash -c "cd /app && bundle exec rails runner /tmp/inspect_state.rb" > /tmp/inspection_output.json 2>/dev/null || true

# Clean up any Rails runner noise (sometimes it outputs deprecation warnings before the JSON)
# We look for the last line that looks like JSON
cat /tmp/inspection_output.json | grep "^{" | tail -n 1 > /tmp/task_result.json

# If extraction failed, create a fallback empty JSON to prevent verifier crash
if [ ! -s /tmp/task_result.json ]; then
    echo '{"error": "Failed to extract data from OpenProject"}' > /tmp/task_result.json
fi

# Add initial state info to the result
INITIAL_COUNT=$(cat /tmp/initial_cf_count.txt 2>/dev/null || echo "0")
# Use jq to merge if available, otherwise simple string injection (risky) or python
python3 -c "
import json
try:
    with open('/tmp/task_result.json', 'r') as f:
        data = json.load(f)
except:
    data = {}
data['initial_cf_count'] = int('$INITIAL_COUNT')
data['task_start'] = int('$TASK_START')
data['task_end'] = int('$TASK_END')
with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f)
"

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="