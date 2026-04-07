#!/bin/bash
echo "=== Exporting refactor_monolithic_protocol result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

echo "Extracting protocol state via Rails runner..."

# Execute a Ruby script to fetch the current state natively through SciNote's models
# This parses out the text content exactly as saved by Trix/ActionText
EXPORT_RUBY=$(cat << 'RUBY'
require 'json'
p = Protocol.where("name LIKE ?", "%Bradford Protein Assay (Draft)%").where(my_module_id: nil).first
result = if p
  steps = p.steps.order(:position).map do |s|
    text = ""
    begin
      soes = s.step_orderable_elements.where(orderable_type: 'StepText')
      if soes.any?
        text = soes.first.orderable.text || ""
      else
        st = StepText.where(step_id: s.id).first
        text = st.text || "" if st
      end
    rescue
      # fallback if associations fail depending on SciNote version
      st = StepText.where(step_id: s.id).first
      text = st.text || "" if st
    end
    {
      id: s.id,
      name: s.name,
      position: s.position,
      text_content: text,
      updated_at: s.updated_at.to_i
    }
  end
  { found: true, id: p.id, step_count: p.steps.count, steps: steps }
else
  { found: false }
end

# Use a marker string to safely extract JSON from Rails logging stdout
puts 'JSON_START'
puts result.to_json
puts 'JSON_END'
RUBY
)

docker exec scinote_web bash -c "bundle exec rails runner '$EXPORT_RUBY'" > /tmp/rails_out.txt

# Extract JSON payload and save to temp file
sed -n '/JSON_START/,/JSON_END/p' /tmp/rails_out.txt | grep -v JSON_START | grep -v JSON_END > /tmp/refactor_protocol_tmp.json

# Copy to final path safely without relying on bash string interpretation
rm -f /tmp/refactor_protocol_result.json 2>/dev/null || sudo rm -f /tmp/refactor_protocol_result.json 2>/dev/null || true
cp /tmp/refactor_protocol_tmp.json /tmp/refactor_protocol_result.json 2>/dev/null || sudo cp /tmp/refactor_protocol_tmp.json /tmp/refactor_protocol_result.json
chmod 666 /tmp/refactor_protocol_result.json 2>/dev/null || sudo chmod 666 /tmp/refactor_protocol_result.json 2>/dev/null || true
rm -f /tmp/refactor_protocol_tmp.json

echo "Result saved to /tmp/refactor_protocol_result.json"
cat /tmp/refactor_protocol_result.json
echo ""
echo "=== Export complete ==="