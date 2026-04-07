#!/bin/bash
echo "=== Setting up create_sales_quotation task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Login to Axelor REST API ──────────────────────────────────────────
echo "--- Logging into Axelor API ---"
axelor_login /tmp/axelor_cookies.txt

# ── 2. Seed customer: Patagonia Inc. ─────────────────────────────────────
echo "--- Seeding customer: Patagonia Inc. ---"

# Check if Patagonia already exists
EXISTING=$(axelor_query "SELECT id FROM base_partner WHERE LOWER(name) = 'patagonia inc.' LIMIT 1;" | tr -d '[:space:]')

if [ -z "$EXISTING" ]; then
    # Create via REST API
    RESULT=$(axelor_create "com.axelor.apps.base.db.Partner" '{
        "name": "Patagonia Inc.",
        "isCustomer": true,
        "isContact": false,
        "partnerTypeSelect": 1,
        "fixedPhone": "+1-805-643-8616",
        "webSite": "https://www.patagonia.com"
    }' /tmp/axelor_cookies.txt)
    echo "Created Patagonia: $RESULT" >&2

    # Fallback: create via SQL if API fails
    if ! partner_exists "Patagonia Inc."; then
        echo "API creation may have failed, trying SQL..." >&2
        axelor_query "INSERT INTO base_partner (name, is_customer, is_contact, partner_type_select, fixed_phone, web_site, version)
                      VALUES ('Patagonia Inc.', true, false, 1, '+1-805-643-8616', 'https://www.patagonia.com', 0)
                      ON CONFLICT DO NOTHING;"
    fi
fi

# Verify customer exists
if partner_exists "Patagonia Inc."; then
    echo "Customer 'Patagonia Inc.' confirmed in database"
else
    echo "WARNING: Could not verify Patagonia Inc. in database"
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
seed_product "Premium Mesh Task Chair" "CHAIR-MSH-001" 549.99 310.00
seed_product "27-inch 4K IPS Monitor" "MON-4K-027" 429.99 265.00

# ── 4. Record initial sale order count ───────────────────────────────────
INITIAL_SO_COUNT=$(get_sale_order_count)
echo "Initial sale order count: ${INITIAL_SO_COUNT}"
echo "${INITIAL_SO_COUNT}" > /tmp/sales_quotation_initial_count

# ── 5. Record task start timestamp ───────────────────────────────────────
date +%s > /tmp/task_start_timestamp

# ── 6. Save setup summary ───────────────────────────────────────────────
cat > /tmp/sales_quotation_setup.json << SETUPEOF
{
  "customer": "Patagonia Inc.",
  "products": [
    {"name": "Ergonomic Standing Desk - Height Adjustable", "qty": 10, "price": 749.99},
    {"name": "Premium Mesh Task Chair", "qty": 15, "price": 549.99},
    {"name": "27-inch 4K IPS Monitor", "qty": 10, "price": 429.99}
  ],
  "initial_so_count": ${INITIAL_SO_COUNT}
}
SETUPEOF

# ── 7. Navigate to Sales module ──────────────────────────────────────────
echo "--- Navigating to Sales module ---"
ensure_axelor_logged_in "${AXELOR_URL}/"
sleep 3

# ── 8. Take initial screenshot ───────────────────────────────────────────
take_screenshot /tmp/create_sales_quotation_initial.png

echo "=== create_sales_quotation task setup complete ==="
echo "Agent should create a sales quotation for Patagonia Inc. with 3 product lines"
