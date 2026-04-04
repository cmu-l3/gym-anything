#!/bin/bash
# Setup script for fillable_hr_form_create task

echo "=== Setting up Fillable HR Form Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Create Documents directory and clear old files
sudo -u ga mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/Apex_New_Hire_Form.odt 2>/dev/null || true
rm -f /home/ga/Documents/form_specs.json 2>/dev/null || true
rm -f /home/ga/Documents/apex_logo.png 2>/dev/null || true

# 2. Generate the Specifications JSON file
cat > /home/ga/Documents/form_specs.json << 'EOF'
{
  "company_info": {
    "name": "Apex Structural Engineering",
    "address": "1200 Broadway St, Suite 400, San Antonio, TX 78215"
  },
  "form_title": "New Hire Data Sheet",
  "instructions": "Please complete all fields below and check the compliance boxes once documents are submitted.",
  "sections": [
    {
      "title": "Employee Information",
      "fields": [
        {"label": "Full Legal Name", "type": "Text Box"},
        {"label": "Street Address", "type": "Text Box"},
        {"label": "City, State, Zip", "type": "Text Box"},
        {"label": "Personal Email", "type": "Text Box"},
        {"label": "Mobile Phone", "type": "Text Box"},
        {"label": "Social Security Number", "type": "Text Box"},
        {"label": "Date of Birth", "type": "Text Box or Date Field"}
      ]
    },
    {
      "title": "Employment Details",
      "fields": [
        {"label": "Start Date", "type": "Date Field (Required)"},
        {"label": "Position Title", "type": "Text Box"}
      ]
    },
    {
      "title": "Compliance Checklist (Check all that apply)",
      "fields": [
        {"label": "I-9 Employment Eligibility Verified", "type": "CheckBox"},
        {"label": "W-4 Federal Tax Form Completed", "type": "CheckBox"},
        {"label": "Direct Deposit Authorization Signed", "type": "CheckBox"},
        {"label": "Employee Handbook Acknowledgment Signed", "type": "CheckBox"}
      ]
    }
  ]
}
EOF
chown ga:ga /home/ga/Documents/form_specs.json
chmod 644 /home/ga/Documents/form_specs.json

# 3. Create a placeholder Company Logo
# We'll use ImageMagick 'convert' if available to make a simple logo,
# otherwise download a placeholder or create a basic image.
if command -v convert >/dev/null 2>&1; then
    convert -size 400x100 xc:white -font DejaVu-Sans-Bold -pointsize 24 -fill darkblue \
    -gravity center -annotate +0+0 "APEX STRUCTURAL\nENGINEERING" \
    /home/ga/Documents/apex_logo.png
else
    # Fallback: Download a generic logo or copy a system icon
    # Using a solid color rect if download fails
    convert -size 300x100 xc:lightblue /home/ga/Documents/apex_logo.png 2>/dev/null || \
    touch /home/ga/Documents/apex_logo.png
fi
chown ga:ga /home/ga/Documents/apex_logo.png

# 4. Ensure OpenOffice is NOT running (agent must launch it)
pkill -f soffice 2>/dev/null || true

# 5. Record start time
date +%s > /tmp/task_start_time.txt
echo "0" > /tmp/initial_file_size.txt

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="
echo "Specs: /home/ga/Documents/form_specs.json"
echo "Logo: /home/ga/Documents/apex_logo.png"
echo "Target: /home/ga/Documents/Apex_New_Hire_Form.odt"