#!/bin/bash
# Task: equipment_acquisition_full_cycle
# Setup: Record baselines for entities, purchases, fixed assets, payments,
#        and journal entries. Ensure payment mode exists. Navigate to dashboard.

echo "=== Setting up equipment_acquisition_full_cycle ==="

source /workspace/scripts/task_utils.sh

if ! type ekylibre_db_query &>/dev/null; then
    ekylibre_db_query() {
        docker exec ekylibre-db psql -U ekylibre -d ekylibre_production -t -A \
            -c "SET search_path TO demo,lexicon,public; $1" 2>/dev/null || echo ""
    }
fi

# Wait for the background Ekylibre build/setup to complete.
# The post_start hook (setup_ekylibre.sh) launches docker build + DB init in the
# background and writes /tmp/ekylibre_service_ready.marker when done.
echo "Waiting for Ekylibre background setup to finish..."
MARKER="/tmp/ekylibre_service_ready.marker"
WAIT_TIMEOUT=3600
WAIT_ELAPSED=0
while [ ! -f "$MARKER" ] && [ "$WAIT_ELAPSED" -lt "$WAIT_TIMEOUT" ]; do
    sleep 10
    WAIT_ELAPSED=$((WAIT_ELAPSED + 10))
    if [ $((WAIT_ELAPSED % 60)) -eq 0 ]; then
        echo "  ...still waiting for Ekylibre setup (${WAIT_ELAPSED}s elapsed)"
    fi
done
if [ -f "$MARKER" ]; then
    echo "Ekylibre background setup complete ($(cat "$MARKER"))"
else
    echo "WARNING: Ekylibre setup marker not found after ${WAIT_TIMEOUT}s, proceeding anyway"
fi

# Now wait for the web interface to respond
wait_for_ekylibre 300
EKYLIBRE_BASE=$(detect_ekylibre_url)

# =============================================================================
# DATA PREPARATION
# =============================================================================

# Ensure an outgoing payment mode exists (bank transfer)
echo "Ensuring outgoing payment mode exists..."
docker exec ekylibre-web bash -c 'cd /app && bundle exec rails runner "
  cash = Cash.find_by(nature: :bank_account) || Cash.first
  if cash
    unless OutgoingPaymentMode.any?
      OutgoingPaymentMode.create!(
        name: \"Virement bancaire\",
        cash: cash,
        with_accounting: true
      )
      puts \"Created outgoing payment mode: Virement bancaire\"
    else
      puts \"Outgoing payment mode already exists: \" + OutgoingPaymentMode.first.name
    end
  else
    puts \"WARNING: No cash/bank account found for payment mode\"
  end
"' 2>/dev/null || echo "WARNING: Payment mode setup had issues, relying on demo data."

# =============================================================================
# DELETE STALE OUTPUTS
# =============================================================================

rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/task_start_time.txt 2>/dev/null || true
rm -f /tmp/initial_entity_count.txt 2>/dev/null || true
rm -f /tmp/initial_purchase_count.txt 2>/dev/null || true
rm -f /tmp/initial_fixed_asset_count.txt 2>/dev/null || true
rm -f /tmp/initial_payment_count.txt 2>/dev/null || true
rm -f /tmp/initial_je_count.txt 2>/dev/null || true
rm -f /tmp/task_initial.png 2>/dev/null || true
rm -f /tmp/task_final.png 2>/dev/null || true

# =============================================================================
# RECORD BASELINES
# =============================================================================

echo "Recording baseline counts..."

INITIAL_ENTITIES=$(ekylibre_db_query "SELECT COUNT(*) FROM entities;" \
    | tr -d '[:space:]')
INITIAL_ENTITIES=${INITIAL_ENTITIES:-0}
echo "$INITIAL_ENTITIES" > /tmp/initial_entity_count.txt

INITIAL_PURCHASES=$(ekylibre_db_query "SELECT COUNT(*) FROM purchases WHERE type = 'PurchaseInvoice';" \
    | tr -d '[:space:]')
INITIAL_PURCHASES=${INITIAL_PURCHASES:-0}
echo "$INITIAL_PURCHASES" > /tmp/initial_purchase_count.txt

INITIAL_ASSETS=$(ekylibre_db_query "SELECT COUNT(*) FROM fixed_assets;" \
    | tr -d '[:space:]')
INITIAL_ASSETS=${INITIAL_ASSETS:-0}
echo "$INITIAL_ASSETS" > /tmp/initial_fixed_asset_count.txt

INITIAL_PAYMENTS=$(ekylibre_db_query "SELECT COUNT(*) FROM outgoing_payments;" \
    | tr -d '[:space:]')
INITIAL_PAYMENTS=${INITIAL_PAYMENTS:-0}
echo "$INITIAL_PAYMENTS" > /tmp/initial_payment_count.txt

INITIAL_JE=$(ekylibre_db_query "SELECT COUNT(*) FROM journal_entries;" \
    | tr -d '[:space:]')
INITIAL_JE=${INITIAL_JE:-0}
echo "$INITIAL_JE" > /tmp/initial_je_count.txt

# =============================================================================
# RECORD TIMESTAMP (after stale cleanup, before browser)
# =============================================================================

date +%s > /tmp/task_start_time.txt

# =============================================================================
# BROWSER SETUP — navigate to the Ekylibre dashboard
# =============================================================================

echo "Navigating Firefox to Ekylibre dashboard..."
ensure_firefox_with_ekylibre "${EKYLIBRE_BASE}/backend"
sleep 5
maximize_firefox
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Baseline entities:          $INITIAL_ENTITIES"
echo "Baseline purchase invoices: $INITIAL_PURCHASES"
echo "Baseline fixed assets:      $INITIAL_ASSETS"
echo "Baseline outgoing payments: $INITIAL_PAYMENTS"
echo "Baseline journal entries:   $INITIAL_JE"
echo "Agent starts at:            ${EKYLIBRE_BASE}/backend (dashboard)"
