#!/bin/bash
echo "=== Setting up annual_policy_handbook_rollout task ==="

source /workspace/scripts/task_utils.sh
wait_for_http "$SENTRIFUGO_URL" 60

# Timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Create directories
POLICIES_DIR="/home/ga/Documents/2026_Policies"
mkdir -p "$POLICIES_DIR"
mkdir -p /home/ga/Desktop

echo "Downloading real-world policy PDFs..."
# Try to download real PDFs, fallback to generic dummy PDFs if network fails
wget -q -O "$POLICIES_DIR/HIPAA_Compliance_v4.pdf" "https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf" || true
wget -q -O "$POLICIES_DIR/Remote_Work_Guidelines_2026.pdf" "https://www.orimi.com/pdf-test.pdf" || true
wget -q -O "$POLICIES_DIR/Code_of_Conduct_2026.pdf" "https://www.africau.edu/images/default/sample.pdf" || true

# Fallback: Create valid PDFs via ImageMagick if downloads failed completely
for file in "HIPAA_Compliance_v4.pdf" "Remote_Work_Guidelines_2026.pdf" "Code_of_Conduct_2026.pdf"; do
    if [ ! -s "$POLICIES_DIR/$file" ]; then
        echo "Fallback: creating PDF $file"
        convert xc:white -page Letter "$POLICIES_DIR/$file" 2>/dev/null || echo "Dummy PDF content" > "$POLICIES_DIR/$file"
    fi
done

chown -R ga:ga "$POLICIES_DIR"

# Record the source hashes for verification (to prove files were actually uploaded)
md5sum "$POLICIES_DIR"/*.pdf > /tmp/source_pdf_hashes.txt

# Create the rollout memo
cat > /home/ga/Desktop/policy_rollout_memo.txt << 'EOF'
============================================================
2026 POLICY ROLLOUT METADATA
============================================================
Please upload the following policies to the HRMS.

File: HIPAA_Compliance_v4.pdf
Title: 2026 HIPAA and Privacy Standards
Description: Mandatory privacy and data security standards for all patient-facing and administrative staff.

File: Remote_Work_Guidelines_2026.pdf
Title: Hybrid and Remote Work Policy
Description: Updated guidelines for telecommuting, core hours, and home office equipment reimbursement.

File: Code_of_Conduct_2026.pdf
Title: Employee Code of Conduct (2026 Edition)
Description: Annual update to the corporate code of conduct, anti-harassment, and ethics guidelines.
============================================================
EOF
chown ga:ga /home/ga/Desktop/policy_rollout_memo.txt

# Start Firefox and navigate to the dashboard
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}"
sleep 3
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup complete ==="