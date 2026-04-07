#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Software TOS Conspicuous Formatting Task ==="

install -d -o ga -g ga /home/ga/Documents
install -d -o ga -g ga /home/ga/Desktop

kill_calligra_processes

# Remove old files if they exist
rm -f /home/ga/Documents/saas_terms_of_service.odt
rm -f /home/ga/Desktop/legal_formatting_instructions.txt

# 1. Create the instructions file on the Desktop
cat << 'EOF' > /home/ga/Desktop/legal_formatting_instructions.txt
CloudScale Analytics - Terms of Service
Formatting Instructions

1. Document Title:
   Make the title "TERMS OF SERVICE" bold, centered, and at least 16pt font.

2. Headings:
   Apply the "Heading 1" style to all 10 numbered section headings (e.g., "1. ACCEPTANCE OF TERMS") and the "Exhibit A: Subscription Tiers" heading.

3. Conspicuous Legal Disclaimers (CRITICAL):
   To comply with UCC requirements for conspicuousness, the entire body text of "8. WARRANTY DISCLAIMER" and "9. LIMITATION OF LIABILITY" MUST be converted to ALL CAPS. (Do not change the text itself, just change its casing to UPPERCASE).

4. Body Text:
   Apply Justified alignment to all standard body paragraphs.

5. Pricing Table:
   Convert the plain text pricing data under "Exhibit A: Subscription Tiers" into a formal table (4 columns, 4 rows). Ensure the data is moved into the table cells and delete the original comma-separated text.
EOF
chown ga:ga /home/ga/Desktop/legal_formatting_instructions.txt

# 2. Create the unformatted TOS document using odfpy
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_paragraph(text=""):
    doc.text.addElement(P(text=text))

# Title and Subtitle
add_paragraph("TERMS OF SERVICE")
add_paragraph("CloudScale Analytics SaaS Agreement")
add_paragraph("Effective Date: January 1, 2026")
add_paragraph("")

# Sections
add_paragraph("1. ACCEPTANCE OF TERMS")
add_paragraph("By accessing or using the CloudScale Analytics service, you agree to be bound by these Terms of Service. If you do not agree to all of these terms, do not use the service.")
add_paragraph("")

add_paragraph("2. DESCRIPTION OF SERVICE")
add_paragraph("CloudScale Analytics provides cloud-based data visualization and analytics tools. The service is subject to modification, updates, and enhancements at our sole discretion.")
add_paragraph("")

add_paragraph("3. USER OBLIGATIONS")
add_paragraph("Users must provide accurate registration information and maintain the security of their account credentials. You are responsible for all activities that occur under your account.")
add_paragraph("")

add_paragraph("4. DATA PRIVACY AND SECURITY")
add_paragraph("Our collection and use of personal data is governed by our Privacy Policy. We implement industry-standard security measures, but users acknowledge that no internet transmission is entirely secure.")
add_paragraph("")

add_paragraph("5. INTELLECTUAL PROPERTY RIGHTS")
add_paragraph("All rights, title, and interest in and to the service, including all intellectual property rights therein, are and will remain the exclusive property of CloudScale Analytics and its licensors.")
add_paragraph("")

add_paragraph("6. SUBSCRIPTION FEES AND PAYMENT")
add_paragraph("Users agree to pay all applicable fees in accordance with the selected subscription tier (see Exhibit A). Fees are non-refundable except as required by law.")
add_paragraph("")

add_paragraph("7. TERM AND TERMINATION")
add_paragraph("These Terms remain in effect until terminated by either party. We may suspend or terminate your access for any breach of these Terms without prior notice.")
add_paragraph("")

add_paragraph("8. WARRANTY DISCLAIMER")
add_paragraph("The services and all related components and information are provided on an \"as is\" and \"as available\" basis without any warranties of any kind, and CloudScale Analytics expressly disclaims any and all warranties, whether express or implied, including, but not limited to, the implied warranties of merchantability, title, fitness for a particular purpose, and non-infringement. Users acknowledge that CloudScale Analytics does not warrant that the service will be uninterrupted, timely, secure, or error-free.")
add_paragraph("")

add_paragraph("9. LIMITATION OF LIABILITY")
add_paragraph("In no event shall CloudScale Analytics, its affiliates, or their respective officers, directors, employees, or agents be liable to any user or any third party for any indirect, incidental, special, punitive, or consequential damages, including loss of profits, lost data, or business interruption, arising out of or in connection with these terms or the use of or inability to use the service, whether based on warranty, contract, tort (including negligence), or any other legal theory, even if CloudScale Analytics has been advised of the possibility of such damages. In no event shall the aggregate liability of CloudScale Analytics exceed the total amounts paid by the user in the twelve months immediately preceding the event giving rise to the claim.")
add_paragraph("")

add_paragraph("10. GENERAL PROVISIONS")
add_paragraph("These Terms constitute the entire agreement between you and CloudScale Analytics. They shall be governed by the laws of the State of Delaware without regard to conflict of law principles.")
add_paragraph("")

add_paragraph("Exhibit A: Subscription Tiers")
add_paragraph("Tier, Monthly Price, Data Limit, Support Level")
add_paragraph("Starter, $49, 100GB, Email Support")
add_paragraph("Professional, $149, 1TB, Priority 24/7")
add_paragraph("Enterprise, Custom, Unlimited, Dedicated Success Manager")

doc.save("/home/ga/Documents/saas_terms_of_service.odt")
PYEOF

chown ga:ga /home/ga/Documents/saas_terms_of_service.odt

# Record timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Launch Calligra Words
launch_calligra_document "/home/ga/Documents/saas_terms_of_service.odt"

# Wait for application window and maximize it
wait_for_window "Calligra Words" 30
WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot showing starting state
take_screenshot /tmp/task_initial_state.png

echo "=== Setup complete ==="