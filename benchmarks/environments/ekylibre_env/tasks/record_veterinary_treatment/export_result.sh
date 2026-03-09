#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting task results ==="

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Use Rails runner to inspect the database objects
# This is much more reliable than raw SQL for complex associations (Interventions -> Targets/Inputs)
echo "Querying Ekylibre database via Rails..."

docker exec ekylibre-web bundle exec rails runner "
  require 'json'
  
  # Switch tenant
  Tenant.switch!(Tenant.first.name) rescue nil

  start_time = Time.at($TASK_START.to_i)
  
  # Find interventions created after task start
  # We look for sanitary/health interventions specifically, but will accept any matching the criteria
  recent_interventions = Intervention.where('created_at > ?', start_time)
  
  results = {
    found: false,
    interventions_found_count: recent_interventions.count,
    matches: []
  }

  recent_interventions.each do |intv|
    # Get targets (Animals)
    targets = intv.targets.map { |t| t.respond_to?(:name) ? t.name : t.try(:target_name) || 'Unknown' }
    
    # Get inputs (Products)
    # Inputs are stored in intervention_inputs table, linked to product_nature_variant
    inputs = intv.inputs.map do |inp| 
      {
        name: inp.product_nature_variant.try(:name),
        quantity: inp.population.to_f
      }
    end

    match_data = {
      id: intv.id,
      procedure_name: intv.procedure.try(:name),
      targets: targets,
      inputs: inputs,
      created_at: intv.created_at
    }
    
    results[:matches] << match_data
    
    # Check criteria
    has_target = targets.any? { |t| t.to_s.match?(/Marguerite/i) }
    has_product = inputs.any? { |i| i[:name].to_s.match?(/Curamycin/i) }
    
    if has_target && has_product
      results[:found] = true
      results[:correct_record] = match_data
    end
  end

  File.write('/tmp/rails_result.json', results.to_json)
" 2>/dev/null || echo '{"error": "Rails runner failed"}' > /tmp/rails_result.json

# Copy result from container to host tmp
docker cp ekylibre-web:/tmp/rails_result.json /tmp/rails_export.json 2>/dev/null || echo "{}" > /tmp/rails_export.json

# Combine into final result JSON
cat > /tmp/task_result.json << EOF
{
  "task_start": $TASK_START,
  "timestamp": "$(date -Iseconds)",
  "screenshot_path": "/tmp/task_final.png",
  "db_result": $(cat /tmp/rails_export.json)
}
EOF

# Permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="