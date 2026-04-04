#!/bin/bash
set -e
echo "=== Setting up task: Upload Compliance Evidence ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# ---------------------------------------------------------------
# 1. Create dummy evidence file
# ---------------------------------------------------------------
mkdir -p /home/ga/Documents/Evidence
cat > /home/ga/Documents/Evidence/Backup_Log_Sept2025.pdf <<EOF
%PDF-1.4
%
1 0 obj
<</Type/Catalog/Pages 2 0 R>>
endobj
2 0 obj
<</Type/Pages/Kids[3 0 R]/Count 1>>
endobj
3 0 obj
<</Type/Page/MediaBox[0 0 595 842]>>
endobj
xref
0 4
0000000000 65535 f
0000000010 00000 n
0000000060 00000 n
0000000111 00000 n
trailer
<</Size 4/Root 1 0 R>>
startxref
190
%%EOF
# Add some random data to make size realistic
head -c 5120 /dev/urandom >> /home/ga/Documents/Evidence/Backup_Log_Sept2025.pdf
chown -R ga:ga /home/ga/Documents/Evidence

# ---------------------------------------------------------------
# 2. Seed Compliance Data in DB
# ---------------------------------------------------------------
echo "Seeding Compliance Data..."

# Use fixed IDs to make logic easier, but handle conflicts
PKG_ID=9001
ITEM_ID=9001
ANALYSIS_ID=9001

# Create Package
# status=1 usually means active/draft
eramba_db_query "INSERT INTO compliance_packages (id, name, description, created, modified) VALUES ($PKG_ID, 'ISO 27001 (Internal)', 'Internal audit framework for security controls.', NOW(), NOW()) ON DUPLICATE KEY UPDATE name=name;"

# Create Item
eramba_db_query "INSERT INTO compliance_package_items (id, compliance_package_id, item_id, name, description, created, modified) VALUES ($ITEM_ID, $PKG_ID, 'A.12.3.1', 'Information Backup', 'Backups of information, software and system images shall be taken and tested regularly in accordance with an agreed backup policy.', NOW(), NOW()) ON DUPLICATE KEY UPDATE name=name;"

# Create Analysis (The target record)
# Eramba's compliance_analysis table links to items. 
# We set 'asset_risk_management'=0 (Not Applicable) or similar defaults if required by schema version.
# Note: Schema might vary, keeping fields minimal based on core Eramba.
eramba_db_query "INSERT INTO compliance_analysis (id, compliance_package_item_id, analysis, findings, created, modified) VALUES ($ANALYSIS_ID, $ITEM_ID, 'Backups are performed daily via cron scripts to offsite storage.', '', NOW(), NOW()) ON DUPLICATE KEY UPDATE analysis=analysis;"

# Clean up any existing attachments for this ID to ensure clean state
eramba_db_query "DELETE FROM attachments WHERE model='ComplianceAnalysis' AND foreign_key=$ANALYSIS_ID;"

echo "$ANALYSIS_ID" > /tmp/target_analysis_id.txt

# ---------------------------------------------------------------
# 3. Launch App
# ---------------------------------------------------------------
# Direct to compliance analysis index to save navigation time, or dashboard
ensure_firefox_eramba "http://localhost:8080/compliance-analysis/index"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="