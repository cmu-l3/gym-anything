#!/bin/bash
echo "=== Setting up update_inventory_stock_levels task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming (ensures updates happen DURING the task)
date +%s > /tmp/task_start_time.txt

# 1. Create the stocktake report on the Desktop
echo "Creating stocktake report file..."
cat > /home/ga/Desktop/stocktake_results.txt << 'EOF'
LABORATORY STOCKTAKE REPORT
Date: 2026-03-08
Auditor: Lab Manager

Please update the ELN inventory with the following physical counts:

1. Ethanol Absolute
   Current System Level: 1000.0 mL
   Physical Measurement: 850.0 mL

2. Acetone
   Current System Level: 500.0 mL
   Physical Measurement: 125.5 mL

3. Toluene
   Current System Level: 250.0 mL
   Physical Measurement: 210.0 mL

Note: All other stock levels (including Methanol) verified as correct.
EOF
chown ga:ga /home/ga/Desktop/stocktake_results.txt

# 2. Seed the database with the inventory and initial values
echo "Seeding database with inventory items..."
docker exec scinote_web bash -c "bundle exec rails runner \"
  begin
    team = Team.first || Team.create!(name: 'Default Team')
    user = User.find_by(email: 'admin@scinote.net') || User.first

    repo = Repository.find_or_create_by!(name: 'Chemical Storage', team_id: team.id)
    repo.update_column(:created_by_id, user.id)

    # Use 0 for 'string_type' default if enum is required, or standard creation
    col = RepositoryColumn.find_or_create_by!(repository_id: repo.id, name: 'Quantity')
    col.update_column(:data_type, 0) rescue nil

    items = {
      'Ethanol Absolute' => '1000.0',
      'Acetone' => '500.0',
      'Toluene' => '250.0',
      'Methanol' => '2000.0',
      'Dichloromethane' => '4000.0'
    }

    items.each do |name, qty|
      row = RepositoryRow.find_or_create_by!(repository_id: repo.id, name: name)
      row.update_column(:created_by_id, user.id) rescue nil
      
      cell = RepositoryCell.find_or_create_by!(repository_row_id: row.id, repository_column_id: col.id)
      cell.update!(value: qty)
      
      # Backdate updated_at so we can detect agent modifications
      cell.update_column(:updated_at, 2.days.ago)
    end
    puts 'Database seed complete.'
  rescue => e
    puts 'Error seeding db: ' + e.message
  end
\""

# 3. Open Firefox to SciNote login
ensure_firefox_running "${SCINOTE_URL}/users/sign_in"

sleep 3
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="