#!/bin/bash
echo "=== Setting up record_outgoing_payment task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Wait for Ekylibre to be ready
wait_for_ekylibre 300

# =============================================================================
# DATA PREPARATION
# =============================================================================
# We need to ensure the supplier and a payment mode exist.
# Using Rails runner inside the container is the most reliable way to interact with the domain model.

echo "Preparing required data (Supplier and Payment Mode)..."

docker exec ekylibre-web bundle exec rails runner "
  # 1. Ensure Supplier Exists
  supplier_name = 'Coopérative Agricole du Centre'
  supplier = Entity.find_by(name: supplier_name)
  unless supplier
    supplier = Entity.create!(
      name: supplier_name,
      nature: :supplier,
      currency: 'EUR'
    )
    puts 'Created supplier: ' + supplier.name
  else
    puts 'Supplier already exists: ' + supplier.name
  end

  # 2. Ensure at least one Bank Account and Payment Mode exist
  # Try to find a financial account (Cash/Bank)
  account = Account.where(nature: :bank_account).first
  unless account
    # Fallback: find any account that can hold a payment mode or create one if needed
    # For simplicity, we assume the demo data provided a bank account.
    # If not, we rely on the existing seed data.
  end
  
  # Ensure there is a payment mode linked to a bank account
  # (Ekylibre usually seeds 'Virement' or 'Chèque')
  mode = PaymentMode.where(nature: :bank_transfer).first
  unless mode
    # If no bank transfer mode, check for check
    mode = PaymentMode.where(nature: :check).first
  end
  
  unless mode && mode.account
     puts 'WARNING: No suitable payment mode found. Task might be difficult.'
  else
     puts 'Payment mode available: ' + mode.name
  end
" || echo "WARNING: Data preparation script had issues, relying on demo data."

# =============================================================================
# INITIAL STATE RECORDING
# =============================================================================

# Record initial number of outgoing payments
INITIAL_COUNT=$(ekylibre_db_query "SELECT COUNT(*) FROM outgoing_payments")
echo "${INITIAL_COUNT:-0}" > /tmp/initial_count.txt
echo "Initial outgoing payment count: ${INITIAL_COUNT:-0}"

# =============================================================================
# BROWSER SETUP
# =============================================================================

# Navigate to the dashboard or the Outgoing Payments list to give the agent a fair start
# The agent should know how to navigate, so we start at the dashboard or list.
EKYLIBRE_URL=$(detect_ekylibre_url)
TARGET_URL="${EKYLIBRE_URL}/backend/outgoing_payments"

echo "Navigating Firefox to $TARGET_URL..."
ensure_firefox_with_ekylibre "$TARGET_URL"

# Wait for page load
sleep 5

# Maximize window
maximize_firefox

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="