#!/bin/bash
# Export script for customize_project_overview task
# Queries the OpenProject database for the grid configuration and exports it.

source /workspace/scripts/task_utils.sh

echo "=== Exporting customize_project_overview result ==="

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Query the Grid configuration via Rails runner
# We extract the list of widget identifiers present on the project's overview page.
# If no custom grid exists (Grids::Overview is nil), we report that (likely failure).

RUBY_SCRIPT=$(cat <<EOF
require 'json'
begin
  p = Project.find_by(identifier: 'mobile-banking-app')
  result = { 
    project_found: false, 
    custom_grid_exists: false, 
    widgets: [] 
  }

  if p
    result[:project_found] = true
    # Grids::Overview stores the layout. 
    # The 'widgets' association or attribute holds the configuration.
    # In recent OpenProject versions, grid.widgets returns the widget objects.
    grid = Grids::Overview.find_by(project_id: p.id)
    
    if grid
      result[:custom_grid_exists] = true
      # Extract widget identifiers (e.g., 'work_packages_overview', 'members', 'news', etc.)
      # The structure can be complex, usually grid.widgets is a list of GridWidget objects,
      # each having an 'identifier' field.
      result[:widgets] = grid.widgets.map { |w| w.identifier }
    end
  end

  puts JSON.generate(result)
rescue => e
  puts JSON.generate({ error: e.message, trace: e.backtrace })
end
EOF
)

# Execute the Ruby script inside the container
echo "Querying database for grid configuration..."
JSON_OUTPUT=$(op_rails "$RUBY_SCRIPT" | grep "^{" | tail -n 1)

# 3. Create the result JSON file
# Use a temp file first to avoid permission issues, then move to final location
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Combine the Rails output with metadata
cat > "$TEMP_JSON" <<EOF
{
  "timestamp": "$(date +%s)",
  "rails_output": $JSON_OUTPUT
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="