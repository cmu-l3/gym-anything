#!/bin/bash
echo "=== Exporting identify_and_list_low_stock_items result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for visual records
take_screenshot /tmp/task_end_screenshot.png

# Generate Ruby script to extract tag and task data reliably from SciNote's internals
cat > /tmp/extract_data.rb << 'RUBYEOF'
require 'json'
res = {tagged: [], untagged: [], task_name: '', task_text: '', task_found: false}

begin
  # 1. Analyze Tagged Inventory Items
  repo = Repository.find_by(name: 'General Chemicals')
  if repo
    repo.repository_rows.each do |row|
      has_tag = false
      
      # Attempt to traverse tag associations gracefully
      if row.respond_to?(:tags)
        has_tag = row.tags.any? { |t| t.name.downcase.include?('restock') }
      elsif row.respond_to?(:repository_row_tags)
        has_tag = row.repository_row_tags.any? { |t| t.tag.name.downcase.include?('restock') rescue false }
      end
      
      # Fallback: Check if the user appended 'restock' directly into the row name
      if !has_tag && row.name.downcase.include?('restock')
        has_tag = true
      end

      if has_tag
        res[:tagged] << row.name
      else
        res[:untagged] << row.name
      end
    end
  end

  # 2. Analyze the 'Weekly Requisition' Task
  exp = Experiment.find_by(name: 'Purchasing')
  if exp
    # Find the newly created task (prioritizing one with "requisition" in the name)
    task = exp.my_modules.find { |m| m.name.downcase.include?('requisition') } || exp.my_modules.order(created_at: :desc).first
    if task
      res[:task_found] = true
      res[:task_name] = task.name || ''
      
      # Collect all text the agent might have entered in the task
      texts = []
      texts << task.description if task.respond_to?(:description) && task.description
      
      if task.respond_to?(:protocols)
        task.protocols.each do |p|
          texts << p.name if p.respond_to?(:name) && p.name
          if p.respond_to?(:steps)
            p.steps.each do |s|
              texts << s.name if s.respond_to?(:name) && s.name
              if s.respond_to?(:step_texts)
                s.step_texts.each { |st| texts << st.text if st.text }
              end
            end
          end
        end
      end
      res[:task_text] = texts.join(' ')
    end
  end

  res[:export_timestamp] = Time.now.iso8601
rescue => e
  res[:error] = e.message
end

File.write('/tmp/internal_result.json', res.to_json)
RUBYEOF

# Execute extraction script
docker cp /tmp/extract_data.rb scinote_web:/tmp/extract_data.rb
docker exec scinote_web bash -c "bundle exec rails runner /tmp/extract_data.rb"

# Retrieve JSON results safely
docker cp scinote_web:/tmp/internal_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="