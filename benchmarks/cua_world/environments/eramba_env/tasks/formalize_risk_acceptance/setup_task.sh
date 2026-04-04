#!/bin/bash
set -e
echo "=== Setting up Formalize Risk Acceptance task ==="

source /workspace/scripts/task_utils.sh

# 1. Record Task Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Prepare Evidence File (The PDF to attach)
mkdir -p /home/ga/Documents
if [ ! -f "/home/ga/Documents/CEO_Risk_SignOff.pdf" ]; then
    echo "Creating dummy evidence PDF..."
    # Create a simple PDF using ImageMagick
    convert -size 595x842 xc:white -font DejaVu-Sans -pointsize 24 -fill black \
        -draw "text 50,50 'OFFICIAL RISK ACCEPTANCE SIGN-OFF'" \
        -draw "text 50,100 'Risk: Legacy ERP - Windows 2008'" \
        -draw "text 50,150 'Approved By: CEO'" \
        -draw "text 50,200 'Date: 2025-01-15'" \
        /home/ga/Documents/CEO_Risk_SignOff.pdf
    chown ga:ga /home/ga/Documents/CEO_Risk_SignOff.pdf
fi

# 3. Seed the Target Risk in Database
# We need a risk named 'Legacy ERP - Windows 2008' with Strategy=Mitigate (3)
echo "Seeding risk record..."
RISK_EXISTS=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT count(*) FROM risks WHERE title='Legacy ERP - Windows 2008' AND deleted=0;" 2>/dev/null || echo "0")

if [ "$RISK_EXISTS" = "0" ]; then
    # Insert new risk
    # Strategy 3 = Mitigate
    docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -e \
        "INSERT INTO risks (title, threats, vulnerabilities, description, risk_mitigation_strategy_id, risk_score, residual_score, review, created, modified) \
         VALUES ('Legacy ERP - Windows 2008', 'Unpatched OS exploits', 'End of Life OS', 'Critical system running on Windows 2008 R2. Cannot be patched.', 3, 8.0, 5.0, DATE_ADD(NOW(), INTERVAL 3 MONTH), NOW(), NOW());" 2>/dev/null
    echo "Risk 'Legacy ERP - Windows 2008' created."
else
    # Reset existing risk to ensure clean state (Mitigate strategy, old description)
    docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -e \
        "UPDATE risks SET risk_mitigation_strategy_id=3, description='Critical system running on Windows 2008 R2. Cannot be patched.', review=DATE_ADD(NOW(), INTERVAL 3 MONTH), modified=NOW() \
         WHERE title='Legacy ERP - Windows 2008';" 2>/dev/null
    # Remove any existing attachments for this risk to ensure clean slate
    docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -e \
        "DELETE FROM attachments WHERE model='Risks' AND foreign_key=(SELECT id FROM risks WHERE title='Legacy ERP - Windows 2008' LIMIT 1);" 2>/dev/null
    echo "Risk 'Legacy ERP - Windows 2008' reset to initial state."
fi

# 4. Ensure Firefox is running and logged in
ensure_firefox_eramba "http://localhost:8080/risks/index"

# 5. Capture Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="