#!/bin/bash
# Setup script for update_purchase_prices task
echo "=== Setting up update_purchase_prices ==="

source /workspace/scripts/task_utils.sh

# Record current standard prices on Purchase 2003 (m_pricelist_version_id=103)
# Products: Mulch 10# (137), Fertilizer #50 (136), Grass Seed Container (125)
MULCH_PRICE=$(idempiere_query "SELECT ROUND(pricestd::numeric,4) FROM m_productprice WHERE m_pricelist_version_id=103 AND m_product_id=137")
FERT_PRICE=$(idempiere_query  "SELECT ROUND(pricestd::numeric,4) FROM m_productprice WHERE m_pricelist_version_id=103 AND m_product_id=136")
GRASS_PRICE=$(idempiere_query "SELECT ROUND(pricestd::numeric,4) FROM m_productprice WHERE m_pricelist_version_id=103 AND m_product_id=125")

MULCH_PRICE=${MULCH_PRICE:-2.7000}
FERT_PRICE=${FERT_PRICE:-18.0000}
GRASS_PRICE=${GRASS_PRICE:-48.0000}

echo "Initial prices — Mulch 10#: $MULCH_PRICE | Fertilizer #50: $FERT_PRICE | Grass Seed Container: $GRASS_PRICE"
echo "${MULCH_PRICE}|${FERT_PRICE}|${GRASS_PRICE}" > /tmp/initial_purchase_prices

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Navigate Firefox to iDempiere dashboard
navigate_to_dashboard

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
