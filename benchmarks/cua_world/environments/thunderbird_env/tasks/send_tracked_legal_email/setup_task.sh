#!/bin/bash
echo "=== Setting up Send Tracked Legal Email Task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Create the necessary legal document (A minimal valid PDF)
mkdir -p /home/ga/Documents
cat << 'EOF' > /tmp/create_pdf.py
import base64
# Minimal valid PDF file
pdf_b64 = b"JVBERi0xLjEKJcKlwrHDqwoKMSAwIG9iago8PAovVHlwZSAvQ2F0YWxvZwovUGFnZXMgMiAwIFIKPj4KZW5kb2JqCgoyIDAgb2JqCjw8Ci9UeXBlIC9QYWdlcwovS2lkcyBbMyAwIFJdCi9Db3VudCAxCj4+CmVuZG9iagoKMyAwIG9iago8PAovVHlwZSAvUGFnZQovUGFyZW50IDIgMCBSCi9NZWRpYUJveCBbMCAwIDYxMiA3OTJdCi9SZXNvdXJjZXMgPDwKL0ZvbnQgPDwKL0YxIDQgMCBSCj4+Cj4+Ci9Db250ZW50cyA1IDAgUgo+PgplbmRvYmoKCjQgMCBvYmoKPDwKL1R5cGUgL0ZvbnQKL1N1YnR5cGUgL1R5cGUxCi9CYXNlRm9udCAvSGVsdmV0aWNhCj4+CmVuZG9iagoKNSAwIG9iago8PAovTGVuZ3RoIDQxCj4+CnN0cmVhbQpCVEQKL0YxIDI0IFRmCjEwMCA3MDAgVGQKKFNldHRsZW1lbnQgQWdyZWVtZW50KSBUagpFVAplbmRzdHJlYW0KZW5kb2JqCgp4cmVmCjAgNgowMDAwMDAwMDAwIDY1NTM1IGYgCjAwMDAwMDAwMTggMDAwMDAgbiAKMDAwMDAwMDA3NyAwMDAwMCBuIAowMDAwMDAwMTM2IDAwMDAwIG4gCjAwMDAwMDAyNTggMDAwMDAgbiAKMDAwMDAwMDM0NiAwMDAwMCBuIAp0cmFpbGVyCjw8Ci9TaXplIDYKL1Jvb3QgMSAwIFIKPj4Kc3RhcnR4cmVmCjQ1MAolJUVPRgo="
with open("/home/ga/Documents/settlement_agreement.pdf", "wb") as f:
    f.write(base64.b64decode(pdf_b64))
EOF
python3 /tmp/create_pdf.py
chown ga:ga /home/ga/Documents/settlement_agreement.pdf

# 3. Ensure Thunderbird is running and pre-configured
start_thunderbird
wait_for_thunderbird_window 30
sleep 3
maximize_thunderbird

# 4. Record initial state of the Sent folder
SENT_MBOX="/home/ga/.thunderbird/default-release/Mail/Local Folders/Sent"
if [ -f "$SENT_MBOX" ]; then
    count_emails_in_mbox "$SENT_MBOX" > /tmp/initial_sent_count.txt
else
    echo "0" > /tmp/initial_sent_count.txt
fi

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="