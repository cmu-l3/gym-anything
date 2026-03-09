#!/bin/bash
set -e
echo "=== Setting up record_animal_movement task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Ekylibre
wait_for_ekylibre 120

echo "Ensuring required data (Animal: Marguerite, Zones) exists via Rails runner..."

# We use a Ruby script inside the container to safely initialize the data state
# using the application's own models.
docker exec ekylibre-web bash -c "cd /app && RAILS_ENV=production bundle exec rails runner '
  # Switch to the demo tenant
  Tenant.switch!(\"demo\")
  
  # 1. Ensure Target Zone exists
  target_name = \"Pature des Saules\"
  target_zone = Zone.where(name: target_name).first
  unless target_zone
    # Create a simple polygon zone
    factory = RGeo::Cartesian::Factory.new(srid: 4326)
    poly = factory.parse_wkt(\"POLYGON((0.1 0.1, 0.1 0.2, 0.2 0.2, 0.2 0.1, 0.1 0.1))\")
    target_zone = Zone.create!(
      name: target_name,
      nature: :cultivable_zone,
      shape: poly
    )
    puts \"Created target zone: #{target_name}\"
  end

  # 2. Ensure Start Zone exists (to ensure a move is actually required)
  start_name = \"Etable Principale\"
  start_zone = Zone.where(name: start_name).first
  unless start_zone
    factory = RGeo::Cartesian::Factory.new(srid: 4326)
    poly = factory.parse_wkt(\"POLYGON((0.3 0.3, 0.3 0.4, 0.4 0.4, 0.4 0.3, 0.3 0.3))\")
    start_zone = Zone.create!(
      name: start_name,
      nature: :building,
      shape: poly
    )
    puts \"Created start zone: #{start_name}\"
  end

  # 3. Ensure Animal exists and is NOT in the target zone
  animal_name = \"Marguerite\"
  animal = Animal.where(name: animal_name).first
  
  if animal.nil?
    # Need to find a valid variant (species) - usually Bovin/Cow
    # We try to find a variant, or fallback to any existing one
    variant = ProductNatureVariant.where(\"name ILIKE ?\", \"%bovin%\").first || ProductNatureVariant.first
    
    animal = Animal.create!(
      name: animal_name,
      number: \"FR\" + rand(1000000000..9999999999).to_s,
      sex: :female,
      birth_date: 3.years.ago,
      variant: variant
    )
    puts \"Created animal: #{animal_name}\"
  end

  # Reset location to start_zone
  # (Update without triggering a movement event if possible, or just force update)
  # In Ekylibre, updating location_id directly might bypass some logic, which is good for setup
  animal.update_column(:location_id, start_zone.id)
  animal.update_column(:updated_at, 1.day.ago) # Backdate to detect new updates
  puts \"Reset animal location to: #{start_zone.name}\"
'"

# Open Firefox to the Animals list
echo "Launching Firefox..."
EKYLIBRE_URL=$(detect_ekylibre_url)
ensure_firefox_with_ekylibre "${EKYLIBRE_URL}/backend/animals"

# Maximize
maximize_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="