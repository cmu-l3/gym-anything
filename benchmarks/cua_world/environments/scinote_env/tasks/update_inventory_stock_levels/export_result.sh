#!/bin/bash
echo "=== Exporting update_inventory_stock_levels result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Extract the current state of the "Chemical Storage" inventory from DB
echo "Exporting inventory state from database..."
docker exec scinote_web bash -c "bundle exec rails runner \"
  require 'json'
  begin
    repo = Repository.find_by(name: 'Chemical Storage')
    results = []
    if repo
      col = RepositoryColumn.find_by(repository_id: repo.id, name: 'Quantity')
      if col
        results = RepositoryRow.where(repository_id: repo.id).map do |row|
          cell = RepositoryCell.find_by(repository_row_id: row.id, repository_column_id: col.id)
          {
            name: row.name,
            value: cell ? cell.value : nil,
            updated_at: cell ? cell.updated_at.to_f : 0.0
          }
        end
      end
    end
    File.write('/tmp/inventory_export.json', results.to_json)
  rescue => e
    File.write('/tmp/inventory_export.json', [].to_json)
  end
\""

# Copy the generated json out of the container
docker cp scinote_web:/tmp/inventory_export.json /tmp/inventory_items.json 2>/dev/null || echo "[]" > /tmp/inventory_items.json

# Merge into final result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "items": $(cat /tmp/inventory_items.json),
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Ensure safe permissions
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="