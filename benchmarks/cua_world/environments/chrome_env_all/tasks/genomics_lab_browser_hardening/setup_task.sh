#!/bin/bash
set -euo pipefail
echo "=== Setting up Genomics Lab Browser Hardening task ==="

export DISPLAY=:1

# 1. Record start time for anti-gaming validation
date +%s > /tmp/task_start_time.txt

# 2. Stop Chrome completely to safely configure profiles
pkill -f "google-chrome" 2>/dev/null || true
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
sleep 2

# 3. Provision target directories
mkdir -p /home/ga/.config/google-chrome-cdp/Default
mkdir -p /home/ga/Research/Downloads
chown -R ga:ga /home/ga/Research

# 4. Create the policy document
cat > /home/ga/Desktop/lab_security_policy.txt << 'EOF'
Genomics Computing Lab - Security & Workflow Policy v1.4

Section 1 - Browser Experiment Flags
Navigate to chrome://flags and enable:
- enable-parallel-downloading
- smooth-scrolling
- reduce-user-agent-request-header

Section 2 - DNS Security
Set DNS-over-HTTPS (Secure DNS) to "Secure" mode using Google Public DNS (https://dns.google/dns-query).

Section 3 - Display Accessibility
Extended reading sessions require adjusted font sizes:
- Default font size: 18
- Default fixed-width font: 15
- Minimum font size: 12

Section 4 - Bookmark Organization
The current flat bookmarks must be organized into 4 folders on the Bookmark Bar:
- "Databases" (dbGaP, GEO, ENCODE, UniProt, Ensembl)
- "Bioinformatics Tools" (Galaxy, BLAST, UCSC Genome Browser, IGV Web, Bioconductor)
- "Journals" (Nature Genetics, Genome Research, PLoS Genetics, Nucleic Acids Research, Bioinformatics)
- "Lab Resources" (protocols.io, bioRxiv, PubMed, GitHub, ORCID)

Section 5 - Notification Policy
Block all site notifications by default, but explicitly ALLOW:
- ncbi.nlm.nih.gov
- usegalaxy.org

Section 6 - Download Management
Set download location to: /home/ga/Research/Downloads
Enable: "Ask where to save each file before downloading"

Section 7 - Session Continuity
On startup, choose: "Continue where you left off"
EOF
chown ga:ga /home/ga/Desktop/lab_security_policy.txt

# 5. Create Flat Bookmarks State
cat > /home/ga/.config/google-chrome-cdp/Default/Bookmarks << 'EOF'
{
   "checksum": "task_start_baseline",
   "roots": {
      "bookmark_bar": {
         "children": [
            { "id": "1", "name": "NCBI dbGaP", "type": "url", "url": "https://www.ncbi.nlm.nih.gov/gap/" },
            { "id": "2", "name": "GEO", "type": "url", "url": "https://www.ncbi.nlm.nih.gov/geo/" },
            { "id": "3", "name": "ENCODE", "type": "url", "url": "https://www.encodeproject.org/" },
            { "id": "4", "name": "UniProt", "type": "url", "url": "https://www.uniprot.org/" },
            { "id": "5", "name": "Ensembl", "type": "url", "url": "https://www.ensembl.org/" },
            { "id": "6", "name": "Galaxy", "type": "url", "url": "https://usegalaxy.org/" },
            { "id": "7", "name": "BLAST", "type": "url", "url": "https://blast.ncbi.nlm.nih.gov/" },
            { "id": "8", "name": "UCSC Genome Browser", "type": "url", "url": "https://genome.ucsc.edu/" },
            { "id": "9", "name": "IGV Web", "type": "url", "url": "https://igv.org/" },
            { "id": "10", "name": "Bioconductor", "type": "url", "url": "https://www.bioconductor.org/" },
            { "id": "11", "name": "Nature Genetics", "type": "url", "url": "https://www.nature.com/ng/" },
            { "id": "12", "name": "Genome Research", "type": "url", "url": "https://genome.cshlp.org/" },
            { "id": "13", "name": "PLoS Genetics", "type": "url", "url": "https://journals.plos.org/plosgenetics/" },
            { "id": "14", "name": "Nucleic Acids Research", "type": "url", "url": "https://academic.oup.com/nar" },
            { "id": "15", "name": "Bioinformatics", "type": "url", "url": "https://academic.oup.com/bioinformatics" },
            { "id": "16", "name": "protocols.io", "type": "url", "url": "https://www.protocols.io/" },
            { "id": "17", "name": "bioRxiv", "type": "url", "url": "https://www.biorxiv.org/" },
            { "id": "18", "name": "PubMed", "type": "url", "url": "https://pubmed.ncbi.nlm.nih.gov/" },
            { "id": "19", "name": "GitHub", "type": "url", "url": "https://github.com/" },
            { "id": "20", "name": "ORCID", "type": "url", "url": "https://orcid.org/" }
         ],
         "id": "bookmark_bar",
         "name": "Bookmarks bar",
         "type": "folder"
      },
      "other": { "children": [], "id": "other", "name": "Other bookmarks", "type": "folder" },
      "synced": { "children": [], "id": "synced", "name": "Mobile bookmarks", "type": "folder" }
   },
   "version": 1
}
EOF

# Provide baseline Preferences to diff against
cat > /home/ga/.config/google-chrome-cdp/Default/Preferences << 'EOF'
{
   "profile": {
      "default_content_setting_values": { "notifications": 1 }
   },
   "webkit": {
      "webprefs": {
         "default_font_size": 16,
         "default_fixed_font_size": 13,
         "minimum_font_size": 0
      }
   }
}
EOF
chown -R ga:ga /home/ga/.config/google-chrome-cdp

# 6. Start CDP Chrome
echo "Starting Chrome..."
su - ga -c "/home/ga/launch_chrome.sh about:blank &"
sleep 5

# 7. Maximize & Focus
wmctrl -r "Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
wmctrl -a "Chrome" 2>/dev/null || true

# 8. Take initial screenshot
scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="