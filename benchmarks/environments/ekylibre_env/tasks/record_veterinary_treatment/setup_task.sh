#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up task: Record Veterinary Treatment ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Wait for Ekylibre to be ready
wait_for_ekylibre 120

echo "Injecting required data (Animal: Marguerite, Product: Curamycin)..."

# We use a Rails runner script to safely inject data into the application context
# This ensures the entities exist for the agent to select
docker exec ekylibre-web bundle exec rails runner '
  # Switch to the tenant (assuming "demo" or first available)
  Tenant.switch!(Tenant.first.name) rescue nil
  
  # 1. Ensure Product "Curamycin" exists
  # Find a veterinary drug nature or fallback to first nature
  nature = ProductNature.where("name ILIKE ?", "%veterinary%").first || ProductNature.where("name ILIKE ?", "%santé%").first || ProductNature.first
  
  product = ProductNatureVariant.find_or_create_by!(name: "Curamycin") do |p|
    p.product_nature = nature
    p.work_number = "CURA-50"
    p.variant_name = "50ml"
  end
  puts "Ensured Product: #{product.name}"

  # 2. Ensure Animal "Marguerite" exists
  # Find a Bovine specie/variant
  species = Variant.where("name ILIKE ?", "%bovin%").first || Variant.first
  
  animal = Animal.find_or_create_by!(name: "Marguerite") do |a|
    a.work_number = "9001"
    a.top_number = "FR1234569001"
    a.sex = "female"
    a.birth_date = 3.years.ago
    a.variant = species
    a.state = "present"
  end
  # Ensure animal is active/present
  animal.update(state: "present") unless animal.state == "present"
  puts "Ensured Animal: #{animal.name} (ID: #{animal.work_number})"
' 2>/dev/null || echo "WARNING: Data injection had issues, but continuing..."

# Record initial count of interventions
INITIAL_COUNT=$(docker exec ekylibre-db psql -U ekylibre -d ekylibre_production -t -A -c "SELECT count(*) FROM interventions" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_count.txt

# Start Firefox and navigate to Dashboard to start fresh
ensure_firefox_with_ekylibre "$(detect_ekylibre_url)/backend"
maximize_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="