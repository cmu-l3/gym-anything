#!/bin/bash
echo "=== Exporting create_reagent_inventory result ==="

source /workspace/scripts/task_utils.sh

# Take final visual evidence
take_screenshot /tmp/task_end_screenshot.png

# Create a robust Ruby script to export the repository schema and data safely
# We use single quotes around RUBYEOF to prevent bash variable interpolation
cat > /tmp/export_script.rb << 'RUBYEOF'
require 'json'
begin
  repo = Repository.where("name ILIKE ?", "%Lab Reagents Q4-2024%").last
  if repo
    cols = RepositoryColumn.where(repository_id: repo.id).map do |c|
      items = RepositoryListItem.where(repository_column_id: c.id).order(:id).map(&:value)
      { name: c.name, data_type: c.data_type, list_items: items }
    end
    
    rows = RepositoryRow.where(repository_id: repo.id).map do |r|
      cells = RepositoryCell.where(repository_row_id: r.id).map do |cell|
        col = RepositoryColumn.find_by(id: cell.repository_column_id)
        val = nil
        
        # Safely attempt to read value from polymorphic cell associations
        tv = RepositoryTextValue.find_by(repository_cell_id: cell.id)
        val = tv.value if tv
        
        nv = RepositoryNumberValue.find_by(repository_cell_id: cell.id)
        val = nv.value if nv
        
        dv = RepositoryDateValue.find_by(repository_cell_id: cell.id)
        val = dv.value.to_s if dv
        
        lv = RepositoryListItemValue.find_by(repository_cell_id: cell.id)
        if lv
          li = RepositoryListItem.find_by(id: lv.repository_list_item_id)
          val = li.value if li
        end
        
        { column_name: (col ? col.name : 'unknown'), value: val }
      end
      { name: r.name, cells: cells }
    end
    
    File.write('/tmp/ruby_export.json', { found: true, name: repo.name, created_at: repo.created_at.to_i, columns: cols, rows: rows }.to_json)
  else
    File.write('/tmp/ruby_export.json', { found: false }.to_json)
  end
rescue => e
  File.write('/tmp/ruby_export.json', { found: false, error: e.message }.to_json)
end
RUBYEOF

echo "Executing extraction script via Rails runner..."
docker cp /tmp/export_script.rb scinote_web:/tmp/export_script.rb
docker exec scinote_web bundle exec rails runner /tmp/export_script.rb

# Copy the exported JSON from the container back to host
docker cp scinote_web:/tmp/ruby_export.json /tmp/create_reagent_inventory_result.json

# Merge with the task start timestamp for anti-gaming validation
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
python3 -c "
import json
try:
    with open('/tmp/create_reagent_inventory_result.json', 'r') as f:
        data = json.load(f)
except Exception:
    data = {'found': False, 'error': 'Failed to load ruby export'}
data['task_start'] = int($TASK_START)
with open('/tmp/create_reagent_inventory_result.json', 'w') as f:
    json.dump(data, f)
"

# Set permissions
chmod 666 /tmp/create_reagent_inventory_result.json

echo "Export contents:"
cat /tmp/create_reagent_inventory_result.json
echo -e "\n=== Export complete ==="