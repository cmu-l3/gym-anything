#!/bin/bash
# Export script for update_purchase_prices task
echo "=== Exporting update_purchase_prices Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Read baseline prices
INITIAL=$(cat /tmp/initial_purchase_prices 2>/dev/null || echo "2.7000|18.0000|48.0000")
INIT_MULCH=$(echo "$INITIAL" | cut -d'|' -f1)
INIT_FERT=$(echo  "$INITIAL" | cut -d'|' -f2)
INIT_GRASS=$(echo "$INITIAL" | cut -d'|' -f3)

# Query current prices on Purchase 2003 (version_id=103)
MULCH_PRICE=$(idempiere_query "SELECT ROUND(pricestd::numeric,4) FROM m_productprice WHERE m_pricelist_version_id=103 AND m_product_id=137")
FERT_PRICE=$(idempiere_query  "SELECT ROUND(pricestd::numeric,4) FROM m_productprice WHERE m_pricelist_version_id=103 AND m_product_id=136")
GRASS_PRICE=$(idempiere_query "SELECT ROUND(pricestd::numeric,4) FROM m_productprice WHERE m_pricelist_version_id=103 AND m_product_id=125")

MULCH_PRICE=${MULCH_PRICE:-0}
FERT_PRICE=${FERT_PRICE:-0}
GRASS_PRICE=${GRASS_PRICE:-0}

echo "Current prices — Mulch 10#: $MULCH_PRICE | Fertilizer #50: $FERT_PRICE | Grass Seed Container: $GRASS_PRICE"

# Escape for JSON (remove any newlines)
MULCH_PRICE=$(echo "$MULCH_PRICE" | tr -d '\n')
FERT_PRICE=$(echo "$FERT_PRICE"   | tr -d '\n')
GRASS_PRICE=$(echo "$GRASS_PRICE" | tr -d '\n')
INIT_MULCH=$(echo "$INIT_MULCH"   | tr -d '\n')
INIT_FERT=$(echo "$INIT_FERT"     | tr -d '\n')
INIT_GRASS=$(echo "$INIT_GRASS"   | tr -d '\n')

cat > /tmp/update_purchase_prices_result.json << EOF
{
    "initial_mulch_price":  "${INIT_MULCH}",
    "initial_fert_price":   "${INIT_FERT}",
    "initial_grass_price":  "${INIT_GRASS}",
    "current_mulch_price":  "${MULCH_PRICE}",
    "current_fert_price":   "${FERT_PRICE}",
    "current_grass_price":  "${GRASS_PRICE}",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "=== Export Complete ==="
