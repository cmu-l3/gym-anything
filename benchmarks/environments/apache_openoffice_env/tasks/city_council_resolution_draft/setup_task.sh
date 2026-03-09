#!/bin/bash
echo "=== Setting up City Council Resolution Draft Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Ensure directories exist
sudo -u ga mkdir -p /home/ga/Documents
sudo -u ga mkdir -p /home/ga/Desktop

# Clean up previous artifacts
rm -f /home/ga/Documents/Resolution_2025_042.odt 2>/dev/null || true

# Create Data JSON
cat > /home/ga/Documents/contract_data.json << 'EOF'
{
  "resolution_number": "2025-042",
  "meeting_date": "March 18, 2025",
  "project": {
    "name": "Meridian Public Library HVAC Replacement",
    "bid_number": "B-2025-11",
    "department": "Public Works"
  },
  "contract": {
    "vendor": "Climate Control Systems, Inc.",
    "amount_numeric": 248500.00,
    "amount_formatted": "$248,500.00",
    "scope": "Demolition of existing cooling towers and installation of new high-efficiency units"
  },
  "financial": {
    "fund": "Capital Improvement Fund (505)",
    "account_code": "505-8200-562.45-01",
    "budget_status": "Appropriated in FY25 Budget"
  },
  "legislative_context": {
    "justification": "The existing HVAC system is 25 years old and has failed three times in the past year, risking damage to library collections.",
    "recommendation": "Staff recommends awarding the contract to the lowest responsible bidder."
  }
}
EOF
chown ga:ga /home/ga/Documents/contract_data.json

# Create Style Guide
cat > /home/ga/Documents/style_guide.txt << 'EOF'
CITY OF MERIDIAN - LEGISLATIVE DRAFTING GUIDE

1. PAGE SETUP
   - Margins: 1.0 inch all sides
   - Font: Times New Roman, 12 pt
   - Line Spacing: Single or 1.15

2. LINE NUMBERING (CRITICAL)
   - All resolutions must have line numbers enabled in the left margin.
   - Go to Tools > Line Numbering.
   - Check "Show numbering".
   - Interval: Every 5 lines.

3. STRUCTURE
   - TITLE: Centered, Bold, Caps (e.g., RESOLUTION NO. 2025-XXX)
   - SUBJECT: Centered, Bold (e.g., A RESOLUTION AUTHORIZING...)
   - PREAMBLE: Series of clauses starting with "WHEREAS,".
     - "WHEREAS" should be in Caps.
   - ENACTMENT: "NOW, THEREFORE, BE IT RESOLVED BY THE CITY COUNCIL OF THE CITY OF MERIDIAN:"
   - BODY: Numbered Sections (Section 1, Section 2...).
   - SIGNATURES: Bottom right for Mayor, bottom left for City Clerk.
EOF
chown ga:ga /home/ga/Documents/style_guide.txt

# Ensure OpenOffice is available (but do not launch it - agent must launch)
if [ -x "/opt/openoffice4/program/soffice" ]; then
    # Create desktop shortcut for convenience
    cat > /home/ga/Desktop/openoffice-writer.desktop << 'DESKTOP'
[Desktop Entry]
Version=1.0
Type=Application
Name=OpenOffice Writer
Comment=Create and edit text documents
Exec=/opt/openoffice4/program/soffice --writer %U
Icon=/opt/openoffice4/program/soffice
Terminal=false
Categories=Office;WordProcessor;
DESKTOP
    chown ga:ga /home/ga/Desktop/openoffice-writer.desktop
    chmod +x /home/ga/Desktop/openoffice-writer.desktop
fi

# Record start time
date +%s > /tmp/task_start_time.txt
echo "0" > /tmp/initial_file_exists

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="