#!/bin/bash
echo "=== Exporting Configure Project Region Field results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Ruby script to inspect the database state
# We check:
# 1. Does the field exist?
# 2. Is it a ProjectCustomField?
# 3. Is it a List format?
# 4. What are the options?
# 5. What value does the Mobile Banking App have?
RUBY_SCRIPT=$(cat <<EOF
require 'json'
begin
  result = {
    field_exists: false,
    field_type: nil,
    field_format: nil,
    options: [],
    project_found: false,
    project_value_raw: nil,
    project_value_resolved: nil
  }

  # Find the field
  f = CustomField.find_by(name: 'Owning Region')
  
  if f
    result[:field_exists] = true
    result[:field_type] = f.type.to_s
    result[:field_format] = f.field_format
    
    # Get options (for List format)
    # OpenProject stores these in custom_options
    if f.respond_to?(:custom_options)
      result[:options] = f.custom_options.map { |o| o.value }
    end
    
    # Check the project value
    p = Project.find_by(identifier: 'mobile-banking-app')
    if p
      result[:project_found] = true
      
      # Get the custom value for this field
      # Note: methods vary slightly by OP version, using safe navigation
      cv = p.custom_values.find_by(custom_field: f)
      
      if cv
        result[:project_value_raw] = cv.value
        
        # For List formats, the value stored is the Option ID
        if f.field_format == 'list' && cv.value.present?
          opt = CustomOption.find_by(id: cv.value)
          result[:project_value_resolved] = opt ? opt.value : nil
        else
          # Fallback for other formats (text, etc)
          result[:project_value_resolved] = cv.value
        end
      end
    end
  end

  puts JSON.generate(result)
rescue => e
  puts JSON.generate({ error: e.message, backtrace: e.backtrace })
end
EOF
)

# Run the ruby script inside the container
echo "Running inspection script..."
op_rails "$RUBY_SCRIPT" > /tmp/rails_output.json 2>/dev/null

# Filter output to get just the JSON (Rails runner might output deprecation warnings)
# We look for the line starting with "{" 
JSON_OUTPUT=$(grep "^{" /tmp/rails_output.json | tail -n 1)

if [ -z "$JSON_OUTPUT" ]; then
    echo "Error: Could not capture valid JSON from Rails runner"
    cat /tmp/rails_output.json
    JSON_OUTPUT="{}"
fi

# Save to final result file
echo "$JSON_OUTPUT" > /tmp/task_result.json

# Add timestamp info
# Use jq to merge if available, otherwise python
if command -v jq &> /dev/null; then
    jq --arg start "$TASK_START" --arg end "$TASK_END" \
       '. + {task_start: $start, task_end: $end}' /tmp/task_result.json > /tmp/task_result.tmp \
       && mv /tmp/task_result.tmp /tmp/task_result.json
else
    # Python fallback for JSON merging
    python3 -c "
import json
with open('/tmp/task_result.json') as f:
    data = json.load(f)
data['task_start'] = '$TASK_START'
data['task_end'] = '$TASK_END'
with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f)
"
fi

echo "Exported JSON:"
cat /tmp/task_result.json
echo "=== Export complete ==="