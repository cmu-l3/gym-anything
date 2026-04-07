#!/bin/bash
echo "=== Exporting configure_inventory_alerts result ==="

source /workspace/scripts/task_utils.sh

# Record end time & take final screenshot
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
take_screenshot /tmp/task_end_screenshot.png

echo "=== Querying inventory state via Rails Runner ==="
cat > /tmp/export_inventory.rb << EOF
require 'json'

begin
  repo = Repository.find_by(name: 'PCR Reagents')
  
  if repo
    # Check if the Minimum Stock column was created (case insensitive)
    min_stock_col = repo.repository_columns.where("name ILIKE ?", "%minimum stock%").first
    has_column = !min_stock_col.nil?
    
    # Check the rows
    row1 = repo.repository_rows.find_by(name: 'Taq DNA Polymerase')
    row2 = repo.repository_rows.find_by(name: 'dNTP Mix 10mM')
    
    # Attempt to extract exact values if the cells exist
    val1 = nil
    val2 = nil
    
    if has_column
      if row1
        cell1 = RepositoryCell.find_by(repository_column_id: min_stock_col.id, repository_row_id: row1.id)
        # Handle variations in SciNote EAV value schemas (value, text_value, numeric_value)
        val1 = cell1.try(:value) || cell1.try(:numeric_value) || cell1.try(:text_value) if cell1
      end
      if row2
        cell2 = RepositoryCell.find_by(repository_column_id: min_stock_col.id, repository_row_id: row2.id)
        val2 = cell2.try(:value) || cell2.try(:numeric_value) || cell2.try(:text_value) if cell2
      end
    end
    
    result = {
      task_start: ${TASK_START},
      task_end: ${TASK_END},
      repo_found: true,
      has_minimum_stock_column: has_column,
      taq_updated_at: row1 ? row1.updated_at.to_f : 0,
      dntp_updated_at: row2 ? row2.updated_at.to_f : 0,
      taq_value: val1.to_s,
      dntp_value: val2.to_s,
      export_timestamp: Time.now.to_i
    }
  else
    result = { repo_found: false, error: "Repository 'PCR Reagents' not found" }
  end
  
  File.write('/tmp/inventory_export.json', result.to_json)
rescue => e
  File.write('/tmp/inventory_export.json', { error: e.message, repo_found: false }.to_json)
end
EOF

# Execute export script
docker exec scinote_web bash -c "bundle exec rails runner /tmp/export_inventory.rb"

# Move the result file securely from container temp space to host accessible temp space
docker exec scinote_web cat /tmp/inventory_export.json > /tmp/configure_inventory_alerts_tmp.json

# Use safe_write_json utility to finalize permissions
safe_write_json "/tmp/configure_inventory_alerts_result.json" "$(cat /tmp/configure_inventory_alerts_tmp.json)"

echo "Result saved to /tmp/configure_inventory_alerts_result.json"
cat /tmp/configure_inventory_alerts_result.json
echo ""
echo "=== Export complete ==="