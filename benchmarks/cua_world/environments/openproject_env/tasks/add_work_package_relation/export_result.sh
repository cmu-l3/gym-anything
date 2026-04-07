#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Exporting add_work_package_relation results ==="

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Run Ruby script inside container to extract precise state
# This script finds the specific WPs, checks for a relation between them, and looks for comments
cat > /tmp/export_logic.rb << 'RUBY_EOF'
require 'json'

begin
  # Find the relevant work packages by partial subject match
  # "source" is the one that follows (Recommendation Engine)
  # "target" is the predecessor (Elasticsearch)
  wp_source = WorkPackage.where("subject LIKE ?", "%recommendation engine%").first
  wp_target = WorkPackage.where("subject LIKE ?", "%Elasticsearch%").first

  result = {
    source_found: !wp_source.nil?,
    target_found: !wp_target.nil?,
    relations: [],
    comments: [],
    final_relation_count: Relation.count
  }

  if wp_source && wp_target
    # Check for direct relations between these two
    # A "follows" relation means source.from_id = target (precedes) OR source.to_id = source (follows) logic
    # But simpler: just find ANY relation linking them and export properties
    rels = Relation.where(from_id: [wp_source.id, wp_target.id], to_id: [wp_source.id, wp_target.id])
    
    result[:relations] = rels.map do |r|
      {
        id: r.id,
        from_id: r.from_id,
        to_id: r.to_id,
        type: r.relation_type,
        lag: r.respond_to?(:lag) ? r.lag : (r.respond_to?(:delay) ? r.delay : 0),
        source_is_from: (r.from_id == wp_source.id),
        target_is_from: (r.from_id == wp_target.id)
      }
    end

    # Get journals/comments for the Source WP (Recommendation Engine)
    # We only care about user notes (comments)
    result[:comments] = wp_source.journals.map do |j|
      {
        id: j.id,
        notes: j.notes,
        created_at: j.created_at.to_i
      }
    end.reject { |j| j[:notes].nil? || j[:notes].empty? }
  end

  puts JSON.generate(result)
rescue => e
  puts JSON.generate({ error: e.message, backtrace: e.backtrace })
end
RUBY_EOF

# Execute the Ruby script in the container
echo "Running export logic in container..."
docker cp /tmp/export_logic.rb openproject:/tmp/export_logic.rb
JSON_OUTPUT=$(docker exec openproject bash -c "cd /app && bin/rails runner -e production /tmp/export_logic.rb" 2>/dev/null | grep "^{")

# 3. Read auxiliary anti-gaming data
INITIAL_REL_COUNT=$(cat /tmp/initial_relation_count.txt 2>/dev/null || echo "0")
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 4. Construct final JSON result
# We wrap the container output in a larger object with host-side metadata
cat > /tmp/task_result.json << EOF
{
  "container_data": $JSON_OUTPUT,
  "initial_relation_count": $INITIAL_REL_COUNT,
  "task_start_time": $TASK_START_TIME,
  "timestamp": "$(date +%s)"
}
EOF

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="