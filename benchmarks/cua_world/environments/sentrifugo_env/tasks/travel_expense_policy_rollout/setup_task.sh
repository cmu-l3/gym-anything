#!/bin/bash
echo "=== Setting up travel_expense_policy_rollout task ==="

source /workspace/scripts/task_utils.sh

# Wait for Sentrifugo to be ready
wait_for_http "$SENTRIFUGO_URL" 60

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# ---- Create Policy Memo on Desktop ----
mkdir -p /home/ga/Desktop

cat > /home/ga/Desktop/TE_Policy_Memo.txt << 'EOF'
TO: HR Admin
FROM: Finance Department
SUBJECT: Q3 Travel & Expense Master Data Rollout

Please configure the following in the Sentrifugo Expenses module immediately.

1. Create these new Expense Categories:
   - International Airfare
   - Domestic Lodging
   - Client Entertainment
   - Conference Registration

2. Create these new Payment Methods:
   - Corporate AMEX
   - Personal Credit Card

3. Test the Workflow:
   Navigate to the Expense Requests section and submit a test expense to ensure 
   the system is accepting attachments correctly.
   
   Details for Test Request:
   - Title: Q3 Sales Conference Tokyo
   - Category: International Airfare
   - Payment Method: Corporate AMEX
   - Amount: 1450.00
   - Attachment: You must upload the "Tokyo_Flight_Receipt.pdf" file located on your Desktop.

Thank you.
EOF

# ---- Create Dummy PDF Receipt ----
echo "Generating dummy PDF receipt..."
# Using ImageMagick to create a realistic-looking PDF receipt
convert -size 600x400 xc:white -font DejaVu-Sans -pointsize 24 -fill black \
    -draw "text 50,50 'ACME GLOBAL AIRLINES'" \
    -draw "text 50,100 'RECEIPT: TOKYO FLIGHT'" \
    -draw "text 50,150 'Passenger: Admin User'" \
    -draw "text 50,200 'Total Amount: $1,450.00'" \
    -draw "text 50,250 'Paid via: Corporate AMEX'" \
    /home/ga/Desktop/Tokyo_Flight_Receipt.pdf 2>/dev/null || true

# Set correct permissions
chown ga:ga /home/ga/Desktop/TE_Policy_Memo.txt
chown ga:ga /home/ga/Desktop/Tokyo_Flight_Receipt.pdf

# ---- Ensure logged in and on the dashboard ----
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/dashboard"
sleep 3
take_screenshot /tmp/task_start_screenshot.png

echo "Task ready: Policy memo and PDF receipt placed on Desktop."
echo "=== Setup complete ==="