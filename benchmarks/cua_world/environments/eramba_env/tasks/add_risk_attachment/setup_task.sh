#!/bin/bash
set -e
echo "=== Setting up add_risk_attachment task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Setup specific task data: Create the PDF evidence file
DOCS_DIR="/home/ga/Documents"
mkdir -p "$DOCS_DIR"
PDF_PATH="$DOCS_DIR/phishing_simulation_report_2025.pdf"

echo "Generating evidence PDF at $PDF_PATH..."

# Create a temporary text file with realistic content
TXT_TMP="/tmp/phishing_report_content.txt"
cat > "$TXT_TMP" << EOF
ACME CORP - SECURITY SIMULATION REPORT
Date: January 15, 2025
Confidentiality: Internal Use Only

EXECUTIVE SUMMARY
------------------------------------------------
Subject: Annual Phishing Simulation Exercise
Target: All Employees (2,500 users)

Results:
- Emails Sent: 2,500
- Emails Opened: 1,850 (74%)
- Link Clicked: 125 (5%)
- Credentials Entered: 12 (0.48%)
- Reported by User: 450 (18%)

Risk Assessment:
The click rate has decreased by 2% since last year. However, credential submission remains a critical risk.
Recommended Actions:
1. Targeted training for repeat clickers.
2. Implementation of FIDO2 keys for high-risk departments.
EOF

# Convert text to PDF using ImageMagick (convert) or enscript+ps2pdf
if command -v convert >/dev/null 2>&1; then
    # Use ImageMagick if available
    convert -font Courier -pointsize 12 -size 612x792 caption:@"$TXT_TMP" "$PDF_PATH" 2>/dev/null || \
    # Fallback to enscript if convert fails or policy prevents it
    (enscript -p - "$TXT_TMP" | ps2pdf - "$PDF_PATH")
else
    # Simple fallback: install enscript/ghostscript or just rename text if strictly needed (but we prefer real PDF)
    # Trying python fallback
    python3 -c "from reportlab.pdfgen import canvas; c = canvas.Canvas('$PDF_PATH'); c.drawString(100, 750, 'ACME CORP PHISHING REPORT'); c.save()" 2>/dev/null || \
    # Ultimate fallback: text file renamed (Eramba checks mime type, but might pass)
    cp "$TXT_TMP" "$PDF_PATH"
fi

rm -f "$TXT_TMP"
chmod 644 "$PDF_PATH"
chown ga:ga "$PDF_PATH"

# 2. Ensure Eramba is running and the target Risk exists
echo "Verifying Eramba state..."

# Ensure Firefox is ready
ensure_firefox_eramba "http://localhost:8080/risks/index"

# Verify/Create the specific risk
RISK_TITLE="Phishing Attacks on Employees"
RISK_CHECK_SQL="SELECT count(*) FROM risks WHERE title='$RISK_TITLE' AND deleted=0;"
RISK_COUNT=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e "$RISK_CHECK_SQL" 2>/dev/null || echo "0")

if [ "$RISK_COUNT" -eq "0" ]; then
    echo "Seeding missing risk: $RISK_TITLE"
    docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -e \
        "INSERT INTO risks (title, description, risk_score, created, modified) VALUES ('$RISK_TITLE', 'Risk of credential theft via social engineering.', 5, NOW(), NOW());" 2>/dev/null || true
fi

# 3. Record initial state (attachment count for this risk)
# Get Risk ID
RISK_ID=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT id FROM risks WHERE title='$RISK_TITLE' AND deleted=0 LIMIT 1;" 2>/dev/null)

if [ -n "$RISK_ID" ]; then
    INITIAL_ATTACHMENTS=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
        "SELECT count(*) FROM attachments WHERE model='Risks' AND foreign_key=$RISK_ID AND deleted=0;" 2>/dev/null || echo "0")
else
    INITIAL_ATTACHMENTS="0"
    echo "WARNING: Could not retrieve Risk ID."
fi

echo "$INITIAL_ATTACHMENTS" > /tmp/initial_attachment_count.txt
date +%s > /tmp/task_start_time.txt

# 4. Take initial screenshot
take_screenshot /tmp/add_risk_attachment_initial.png

echo "=== Setup complete ==="
echo "Target Risk: $RISK_TITLE"
echo "Evidence File: $PDF_PATH"