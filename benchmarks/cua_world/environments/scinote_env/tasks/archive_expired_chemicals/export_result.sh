#!/bin/bash
set -e
echo "=== Exporting archive_expired_chemicals result ==="

# Record task end time
date +%s > /tmp/task_end_time.txt

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

echo "=== Extracting inventory status via Rails ==="

# Create a Ruby script to export the archival status of the items
cat << 'RUBYEOF' > /tmp/export_inventory.rb
require 'json'

begin
  repo = Repository.find_by(name: 'Chemical Storage')
  
  if repo
    # Use unscoped to ensure we retrieve rows even if they've been soft-deleted/archived
    rows = RepositoryRow.unscoped.where(repository_id: repo.id)
    
    results = rows.map do |r|
      # Determine archival status checking both common SciNote patterns
      is_archived = false
      is_archived = true if r.respond_to?(:archived) && r.archived
      is_archived = true if r.respond_to?(:deleted_at) && r.deleted_at.present?
      
      { 
        name: r.name, 
        archived: is_archived,
        updated_at: r.updated_at.to_i
      }
    end
    
    output = { success: true, items: results }
  else
    output = { success: false, error: 'Repository Chemical Storage not found' }
  end
  
  File.write('/tmp/archive_chemicals_result.json', output.to_json)
  puts "Exported successfully."
rescue => e
  output = { success: false, error: e.message }
  File.write('/tmp/archive_chemicals_result.json', output.to_json)
  puts "Error during export: #{e.message}"
end
RUBYEOF

# Execute the export script inside the container
docker cp /tmp/export_inventory.rb scinote_web:/tmp/export_inventory.rb
docker exec scinote_web bundle exec rails runner /tmp/export_inventory.rb

# Copy the result JSON out of the container to the host filesystem
docker cp scinote_web:/tmp/archive_chemicals_result.json /tmp/archive_chemicals_result.json

# Ensure correct permissions for the verifier
chmod 666 /tmp/archive_chemicals_result.json 2>/dev/null || sudo chmod 666 /tmp/archive_chemicals_result.json 2>/dev/null || true

echo "Result JSON:"
cat /tmp/archive_chemicals_result.json
echo ""

echo "=== Export complete ==="