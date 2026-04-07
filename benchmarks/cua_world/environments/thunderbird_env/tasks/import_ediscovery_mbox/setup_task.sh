#!/bin/bash
set -e

echo "=== Setting up eDiscovery task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 1. Create a lightweight, authentic PDF for ground truth natively (no internet required)
# We use Python to write a perfect minimal PDF structure to avoid Bash escaping issues
python3 -c "
pdf_content = b'%PDF-1.4\n1 0 obj <</Type /Catalog /Pages 2 0 R>> endobj\n2 0 obj <</Type /Pages /Kids [3 0 R] /Count 1>> endobj\n3 0 obj <</Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources <<>>>> endobj\n4 0 obj <</Length 0>> stream\nendstream\nendobj\nxref\n0 5\n0000000000 65535 f \n0000000009 00000 n \n0000000056 00000 n \n0000000111 00000 n \n0000000212 00000 n \ntrailer <</Size 5 /Root 1 0 R>>\nstartxref\n256\n%%EOF\n'
with open('/tmp/ground_truth_fw9.pdf', 'wb') as f:
    f.write(pdf_content)
"
chmod 400 /tmp/ground_truth_fw9.pdf

# 2. Safely base64 encode the PDF for MIME embedding
python3 -c "
import base64
with open('/tmp/ground_truth_fw9.pdf', 'rb') as f:
    b64 = base64.b64encode(f.read()).decode('utf-8')
wrapped = '\n'.join(b64[i:i+76] for i in range(0, len(b64), 76))
with open('/tmp/pdf_base64.txt', 'w') as f:
    f.write(wrapped)
"

# 3. Construct the MBOX file
MBOX_FILE="/tmp/client_archive.mbox"
> "$MBOX_FILE"

# Add realistic noise from the environment's pre-loaded ham corpus if available
if [ -d "/workspace/assets/emails/ham" ]; then
    count=0
    for eml in /workspace/assets/emails/ham/*; do
        if [ -f "$eml" ] && [ $count -lt 4 ]; then
            SENDER=$(grep -m1 "^From:" "$eml" | sed 's/From: //' || echo "sender@example.com")
            DATE=$(grep -m1 "^Date:" "$eml" | sed 's/Date: //' || echo "Mon Jan 01 00:00:00 2024")
            echo "From ${SENDER} ${DATE}" >> "$MBOX_FILE"
            cat "$eml" >> "$MBOX_FILE"
            echo "" >> "$MBOX_FILE"
            count=$((count+1))
        fi
    done
fi

# Add the target email with the PDF attachment
echo "From legal@example.com Mon Mar 09 10:00:00 2026" >> "$MBOX_FILE"
cat << EOF >> "$MBOX_FILE"
From: "Legal Team" <legal@example.com>
To: "Attorney" <attorney@example.com>
Date: Mon, 09 Mar 2026 10:00:00 +0000
Subject: Fwd: Executed W-9 Form for Project
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="BOUNDARY_W9_12345"

--BOUNDARY_W9_12345
Content-Type: text/plain; charset="utf-8"

Please find the attached executed W-9 form for the upcoming vendor dispute filing.

Regards,
Legal Team

--BOUNDARY_W9_12345
Content-Type: application/pdf; name="fw9.pdf"
Content-Disposition: attachment; filename="fw9.pdf"
Content-Transfer-Encoding: base64

EOF

cat /tmp/pdf_base64.txt >> "$MBOX_FILE"

cat << EOF >> "$MBOX_FILE"

--BOUNDARY_W9_12345--

EOF

# 4. Prepare required directories and create the ZIP archive
su - ga -c "mkdir -p /home/ga/Downloads"
su - ga -c "mkdir -p /home/ga/Documents/Case_Files"

# Use python zipfile module since 'zip' command isn't guaranteed on all slim images
python3 -c "
import zipfile
with zipfile.ZipFile('/home/ga/Downloads/ediscovery_export.zip', 'w', zipfile.ZIP_DEFLATED) as zf:
    zf.write('/tmp/client_archive.mbox', 'client_archive.mbox')
"
chown ga:ga /home/ga/Downloads/ediscovery_export.zip

# Cleanup temp build files
rm "$MBOX_FILE"
rm /tmp/pdf_base64.txt

# 5. Application Launch
if ! pgrep -f "thunderbird" > /dev/null; then
    echo "Starting Thunderbird..."
    su - ga -c "DISPLAY=:1 thunderbird -profile /home/ga/.thunderbird/default-release &"
    sleep 8
fi

# Maximize and Focus window
DISPLAY=:1 wmctrl -r "Thunderbird" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Thunderbird" 2>/dev/null || true

# Allow UI to stabilize and take the initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="