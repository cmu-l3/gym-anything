#!/bin/bash
echo "=== Setting up export_won_opportunities_csv task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for log verification)
date +%s > /tmp/task_start_time.txt
# Ensure clean state for output directories
rm -f /home/ga/Documents/closed_won_deals.csv 2>/dev/null || true
rm -f /home/ga/Downloads/*.csv 2>/dev/null || true

# 1. Clean existing opportunities to ensure controlled environment
echo "Cleaning existing opportunities..."
suitecrm_db_query "UPDATE opportunities SET deleted=1;"

# 2. Inject realistic Opportunities via SQL
echo "Injecting target 'Closed Won' opportunities..."

# Generate UUIDs and insert 8 Closed Won deals
WON_DEALS=(
    "Q3 Server Rack Expansion - NexusHealth"
    "Bulk Cable Procurement - OmegaCorp"
    "Office Network Upgrade - TechCorp"
    "Enterprise License Renewal - Globex"
    "Consulting Services - Initech"
    "Hardware Refresh - Umbrella Corp"
    "Cloud Migration - Stark Industries"
    "Security Audit - Wayne Enterprises"
)

for name in "${WON_DEALS[@]}"; do
    UUID=$(cat /proc/sys/kernel/random/uuid)
    AMOUNT=$((10000 + RANDOM % 90000))
    suitecrm_db_query "INSERT INTO opportunities (id, name, date_entered, date_modified, modified_user_id, created_by, description, deleted, amount, amount_usdollar, currency_id, sales_stage, probability) VALUES ('$UUID', '$name', UTC_TIMESTAMP(), UTC_TIMESTAMP(), '1', '1', 'Target Deal', 0, $AMOUNT, $AMOUNT, '-99', 'Closed Won', 100);"
done

echo "Injecting noise opportunities..."

NOISE_DEALS=(
    "Initial Consultation - Delta Logistics|Prospecting|10"
    "Lost: Pricing - TechFlow Systems|Closed Lost|0"
    "Q4 Software Rollout - CyberDyne|Qualification|20"
    "Server Maintenance - Massive Dynamic|Needs Analysis|25"
    "Employee Laptops - Dunder Mifflin|Value Proposition|30"
    "Router Replacement - Pied Piper|Id. Decision Makers|40"
    "Security System - Hooli|Perception Analysis|50"
    "Database Migration - Aviato|Proposal/Price Quote|65"
    "Cloud Storage - Erlich Bachman|Negotiation/Review|80"
    "Data Center Cooling - Tyrell Corp|Prospecting|10"
    "Lost: Competitor - Weyland-Yutani|Closed Lost|0"
    "Network Cabling - Oscorp|Qualification|20"
    "Backup Servers - InGen|Needs Analysis|25"
    "Telecom Setup - Virtucon|Value Proposition|30"
    "VoIP Implementation - Initrode|Id. Decision Makers|40"
    "Lost: Budget - Soylent Corp|Closed Lost|0"
    "Fiber Optic Install - BNL|Proposal/Price Quote|65"
)

for deal in "${NOISE_DEALS[@]}"; do
    IFS='|' read -r name stage prob <<< "$deal"
    UUID=$(cat /proc/sys/kernel/random/uuid)
    AMOUNT=$((5000 + RANDOM % 50000))
    suitecrm_db_query "INSERT INTO opportunities (id, name, date_entered, date_modified, modified_user_id, created_by, description, deleted, amount, amount_usdollar, currency_id, sales_stage, probability) VALUES ('$UUID', '$name', UTC_TIMESTAMP(), UTC_TIMESTAMP(), '1', '1', 'Noise Deal', 0, $AMOUNT, $AMOUNT, '-99', '$stage', $prob);"
done

echo "Total active opportunities: $(suitecrm_count 'opportunities' 'deleted=0')"

# 3. Ensure logged in and navigate to Opportunities list
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Opportunities&action=index"
sleep 4

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="