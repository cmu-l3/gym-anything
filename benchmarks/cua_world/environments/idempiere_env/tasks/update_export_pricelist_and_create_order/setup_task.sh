#!/bin/bash
# Setup script for update_export_pricelist_and_create_order task
echo "=== Setting up update_export_pricelist_and_create_order ==="

source /workspace/scripts/task_utils.sh

# Record current Export 2003 (m_pricelist_version_id=105) prices for 3 patio products
# Products: Patio Chair (133), Patio Table (134), Patio Sun Screen (135)
CHAIR_PRICE=$(idempiere_query "SELECT ROUND(pricestd::numeric,4) FROM m_productprice WHERE m_pricelist_version_id=105 AND m_product_id=133")
TABLE_PRICE=$(idempiere_query "SELECT ROUND(pricestd::numeric,4) FROM m_productprice WHERE m_pricelist_version_id=105 AND m_product_id=134")
SCREEN_PRICE=$(idempiere_query "SELECT ROUND(pricestd::numeric,4) FROM m_productprice WHERE m_pricelist_version_id=105 AND m_product_id=135")

CHAIR_PRICE=${CHAIR_PRICE:-30.6900}
TABLE_PRICE=${TABLE_PRICE:-61.3600}
SCREEN_PRICE=${SCREEN_PRICE:-20.4500}

echo "Initial Export 2003 prices — Patio Chair: $CHAIR_PRICE | Patio Table: $TABLE_PRICE | Patio Sun Screen: $SCREEN_PRICE"
echo "${CHAIR_PRICE}|${TABLE_PRICE}|${SCREEN_PRICE}" > /tmp/initial_export_prices

# Record existing SO IDs for Patio Fun Inc. (c_bpartner_id=121)
idempiere_query "SELECT c_order_id FROM c_order WHERE ad_client_id=11 AND c_bpartner_id=121 AND issotrx='Y' ORDER BY c_order_id" > /tmp/initial_patiofun_so_ids

INIT_SO_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_order WHERE ad_client_id=11 AND c_bpartner_id=121 AND issotrx='Y'")
echo "Initial Patio Fun Inc. SO count: ${INIT_SO_COUNT:-0}"
echo "${INIT_SO_COUNT:-0}" > /tmp/initial_patiofun_so_count

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Navigate to dashboard
navigate_to_dashboard

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
