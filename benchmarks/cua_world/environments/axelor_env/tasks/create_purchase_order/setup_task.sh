#!/bin/bash
echo "=== Setting up create_purchase_order task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Login to Axelor REST API ──────────────────────────────────────────
echo "--- Logging into Axelor API ---"
axelor_login /tmp/axelor_cookies.txt

# ── 2. Seed supplier: Grainger Industrial Supply ─────────────────────────
echo "--- Seeding supplier: Grainger Industrial Supply ---"

EXISTING=$(axelor_query "SELECT id FROM base_partner WHERE LOWER(name) = 'grainger industrial supply' LIMIT 1;" | tr -d '[:space:]')

if [ -z "$EXISTING" ]; then
    axelor_create "com.axelor.apps.base.db.Partner" '{
        "name": "Grainger Industrial Supply",
        "isSupplier": true,
        "isCustomer": false,
        "isContact": false,
        "partnerTypeSelect": 1,
        "fixedPhone": "+1-800-472-4643",
        "webSite": "https://www.grainger.com"
    }' /tmp/axelor_cookies.txt

    # Fallback SQL
    if ! partner_exists "Grainger Industrial Supply"; then
        echo "API creation may have failed, trying SQL..." >&2
        axelor_query "INSERT INTO base_partner (name, is_supplier, is_customer, is_contact, partner_type_select, fixed_phone, web_site, version)
                      VALUES ('Grainger Industrial Supply', true, false, false, 1, '+1-800-472-4643', 'https://www.grainger.com', 0)
                      ON CONFLICT DO NOTHING;"
    fi
fi

if partner_exists "Grainger Industrial Supply"; then
    echo "Supplier 'Grainger Industrial Supply' confirmed in database"
else
    echo "WARNING: Could not verify Grainger Industrial Supply in database"
fi

# ── 3. Seed products ────────────────────────────────────────────────────
echo "--- Seeding products ---"

seed_product() {
    local name="$1"
    local code="$2"
    local sale_price="$3"
    local purchase_price="$4"

    local existing
    existing=$(axelor_query "SELECT id FROM base_product WHERE LOWER(name) = LOWER('${name}') LIMIT 1;" | tr -d '[:space:]')
    if [ -z "$existing" ]; then
        axelor_create "com.axelor.apps.base.db.Product" "{
            \"name\": \"${name}\",
            \"code\": \"${code}\",
            \"salePrice\": ${sale_price},
            \"purchasePrice\": ${purchase_price},
            \"productTypeSelect\": \"storable\",
            \"sellable\": true,
            \"purchasable\": true
        }" /tmp/axelor_cookies.txt

        # Fallback SQL
        existing=$(axelor_query "SELECT id FROM base_product WHERE LOWER(name) = LOWER('${name}') LIMIT 1;" | tr -d '[:space:]')
        if [ -z "$existing" ]; then
            axelor_query "INSERT INTO base_product (name, code, sale_price, purchase_price, product_type_select, sellable, purchasable, version, dtype)
                          VALUES ('${name}', '${code}', ${sale_price}, ${purchase_price}, 'storable', true, true, 0, 'Product')
                          ON CONFLICT DO NOTHING;"
        fi
    fi
    echo "Product '${name}': seeded"
}

seed_product "Ergonomic Standing Desk - Height Adjustable" "DESK-ERG-001" 749.99 420.00
seed_product "USB-C Docking Station Pro" "DOCK-USC-001" 199.99 105.00
seed_product "Noise-Cancelling Headset Pro" "HEAD-NC-001" 349.99 185.00

# ── 4. Record initial purchase order count ───────────────────────────────
INITIAL_PO_COUNT=$(get_purchase_order_count)
echo "Initial purchase order count: ${INITIAL_PO_COUNT}"
echo "${INITIAL_PO_COUNT}" > /tmp/purchase_order_initial_count

# ── 5. Record task start timestamp ───────────────────────────────────────
date +%s > /tmp/task_start_timestamp

# ── 6. Save setup summary ───────────────────────────────────────────────
cat > /tmp/purchase_order_setup.json << SETUPEOF
{
  "supplier": "Grainger Industrial Supply",
  "products": [
    {"name": "Ergonomic Standing Desk - Height Adjustable", "qty": 20, "price": 420.00},
    {"name": "USB-C Docking Station Pro", "qty": 50, "price": 105.00},
    {"name": "Noise-Cancelling Headset Pro", "qty": 30, "price": 185.00}
  ],
  "initial_po_count": ${INITIAL_PO_COUNT}
}
SETUPEOF

# ── 7. Navigate to Purchase module ──────────────────────────────────────
echo "--- Navigating to Purchase module ---"
ensure_axelor_logged_in "${AXELOR_URL}/"
sleep 3

# ── 8. Take initial screenshot ───────────────────────────────────────────
take_screenshot /tmp/create_purchase_order_initial.png

echo "=== create_purchase_order task setup complete ==="
echo "Agent should create a purchase order from Grainger Industrial Supply with 3 product lines and confirm it"
