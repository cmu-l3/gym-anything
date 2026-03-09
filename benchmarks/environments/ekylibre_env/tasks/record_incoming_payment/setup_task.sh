#!/bin/bash
set -e
echo "=== Setting up record_incoming_payment task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Wait for Ekylibre to be ready
wait_for_ekylibre 120

EKYLIBRE_URL=$(detect_ekylibre_url)
echo "Ekylibre URL: $EKYLIBRE_URL"
TENANT="demo"

# ============================================================
# 1. Ensure Payer Entity Exists
# ============================================================
echo "Ensuring payer entity 'Coopérative Agricole de Charente' exists..."
ENTITY_CHECK=$(ekylibre_db_query "SET search_path TO ${TENANT}, postgis, lexicon, public; SELECT count(*) FROM entities WHERE full_name = 'Coopérative Agricole de Charente';" 2>/dev/null || echo "0")

if [ "$ENTITY_CHECK" = "0" ] || [ -z "$ENTITY_CHECK" ]; then
    echo "Creating payer entity via Rails runner..."
    docker exec ekylibre-web bash -c "cd /app && RAILS_ENV=production bundle exec rails runner '
      Apartment::Tenant.switch(\"${TENANT}\") do
        unless Entity.where(full_name: \"Coopérative Agricole de Charente\").exists?
          e = Entity.new(
            nature: :organization,
            last_name: \"Coopérative Agricole de Charente\",
            active: true,
            client: true
          )
          e.save!
          puts \"Entity created: #{e.full_name}\"
        end
      end
    '" 2>/dev/null || true
fi

# ============================================================
# 2. Ensure Payment Mode Exists
# ============================================================
echo "Ensuring payment mode exists..."
MODE_CHECK=$(ekylibre_db_query "SET search_path TO ${TENANT}, postgis, lexicon, public; SELECT count(*) FROM incoming_payment_modes;" 2>/dev/null || echo "0")

if [ "$MODE_CHECK" = "0" ] || [ -z "$MODE_CHECK" ]; then
    echo "Creating 'Chèque' payment mode via Rails runner..."
    docker exec ekylibre-web bash -c "cd /app && RAILS_ENV=production bundle exec rails runner '
      Apartment::Tenant.switch(\"${TENANT}\") do
        cash = Cash.find_by(nature: :bank_account) || Cash.first
        if cash
          IncomingPaymentMode.create!(name: \"Chèque\", cash: cash, with_accounting: true, active: true)
          puts \"Payment mode created\"
        end
      end
    '" 2>/dev/null || true
fi

# ============================================================
# 3. Record Initial State
# ============================================================
INITIAL_COUNT=$(ekylibre_db_query "SET search_path TO ${TENANT}, postgis, lexicon, public; SELECT count(*) FROM incoming_payments;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_incoming_payments_count.txt
echo "Initial incoming payments count: $INITIAL_COUNT"

# ============================================================
# 4. Open Firefox to Incoming Payments Page
# ============================================================
echo "Opening Firefox..."
ensure_firefox_with_ekylibre "${EKYLIBRE_URL}/backend/incoming_payments"
sleep 5
maximize_firefox
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="