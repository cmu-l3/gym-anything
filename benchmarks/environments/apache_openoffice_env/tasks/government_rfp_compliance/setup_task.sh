#!/bin/bash
echo "=== Setting up Government RFP Compliance Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Create Documents directory
sudo -u ga mkdir -p /home/ga/Documents

# 2. clean up previous artifacts
rm -f /home/ga/Documents/TechFlow_Proposal_Volume_I.odt 2>/dev/null || true
rm -f /home/ga/Documents/draft_proposal.json 2>/dev/null || true
rm -f /home/ga/Documents/formatting_requirements.txt 2>/dev/null || true

# 3. Create Draft Proposal Content (JSON)
cat > /home/ga/Documents/draft_proposal.json << 'EOF'
{
  "title": "Municipal Wi-Fi Expansion Project - Technical Volume",
  "sections": [
    {
      "heading": "Executive Summary",
      "content": "TechFlow Solutions is pleased to submit this proposal to the City of Oakdale. Our solution leverages next-generation 802.11ax (Wi-Fi 6) technology to provide seamless, high-speed outdoor coverage across the downtown district. We understand the City's need for a scalable, secure, and public-facing network that supports both municipal operations and free public access."
    },
    {
      "heading": "Technical Approach",
      "content": "Our proposed architecture utilizes a mesh network topology with redundant backhaul links. We will deploy 45 Cisco Catalyst 9124AX outdoor access points mounted on existing streetlights. The network will operate on both 2.4GHz and 5GHz bands, ensuring compatibility with legacy devices while maximizing throughput for modern users. Centralized management will be provided via a cloud-based controller."
    },
    {
      "heading": "Implementation Plan",
      "content": "Phase 1 (Weeks 1-4) will consist of site surveys and RF planning. Phase 2 (Weeks 5-8) will involve hardware installation and cabling. Phase 3 (Weeks 9-10) covers configuration, testing, and optimization. We have allocated a dedicated Project Manager, Sarah Jenkins, to oversee the deployment and ensure minimal disruption to city activities."
    },
    {
      "heading": "Past Performance",
      "content": "TechFlow has successfully delivered similar municipal Wi-Fi projects for the City of Springfield (2023) and Pine Valley Township (2024). In Springfield, we deployed 120 nodes covering 2.5 square miles, achieving 99.99% uptime in the first year of operation. Reference contacts are available upon request."
    }
  ]
}
EOF
chown ga:ga /home/ga/Documents/draft_proposal.json

# 4. Create Formatting Requirements Text
cat > /home/ga/Documents/formatting_requirements.txt << 'EOF'
SOLICITATION INSTRUCTIONS - SECTION L
RFP #2026-WIFI-09

FORMATTING REQUIREMENTS FOR VOLUME I (TECHNICAL):

1. PAGE LAYOUT
   - Margins: 1.00 inch (2.54 cm) on all sides (Top, Bottom, Left, Right).
   - Orientation: Portrait.
   - Paper Size: Letter (8.5 x 11 inches).

2. HEADERS AND FOOTERS
   - Header: Must contain exactly "RFP #2026-WIFI-09 - Technical Volume".
   - Footer: Must contain page numbers.

3. TYPOGRAPHY
   - Section Headings: Must use a distinct Heading style (e.g., Heading 1).
   - Body Text: Standard readable font (Times New Roman or Arial).

FAILURE TO COMPLY WITH MARGIN OR HEADER REQUIREMENTS WILL RESULT IN DISQUALIFICATION.
EOF
chown ga:ga /home/ga/Documents/formatting_requirements.txt

# 5. Record initial state
date +%s > /tmp/task_start_time.txt
echo "0" > /tmp/initial_file_exists.txt

# 6. Ensure OpenOffice Writer is NOT running (to test launch)
# OR start it if we want to save time. Let's start it to be helpful.
if ! pgrep -f "soffice" > /dev/null; then
    echo "Starting OpenOffice Writer..."
    su - ga -c "DISPLAY=:1 /opt/openoffice4/program/soffice --writer &"
    
    # Wait for window
    for i in {1..30}; do
        if wmctrl -l | grep -i "OpenOffice Writer"; then
            echo "OpenOffice Writer started."
            break
        fi
        sleep 1
    done
fi

# 7. Maximize window
DISPLAY=:1 wmctrl -r "OpenOffice Writer" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 8. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="