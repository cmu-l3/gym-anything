#!/bin/bash
# Setup for Safety Documentation Library task
set -e

echo "=== Setting up Safety Documentation Library Task ==="

# 1. Kill any running Edge instances to ensure clean state
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
sleep 1

# 2. Clean up previous run artifacts
rm -rf /home/ga/Documents/SafetyLibrary 2>/dev/null || true
rm -f /home/ga/Desktop/doc_requirements.txt 2>/dev/null || true

# 3. Create the requirements document
cat > /home/ga/Desktop/doc_requirements.txt << 'EOF'
SAFETY DOCUMENTATION LIBRARY - SETUP REQUIREMENTS

Project: Commercial Building Maintenance Contract #2024-BM-0847

You are required to set up a digital safety documentation library for the
maintenance team. All documents must be sourced from official US government
agency websites only.

Required Directory Structure:
  ~/Documents/SafetyLibrary/
  ├── OSHA/     (Occupational Safety & Health Administration documents)
  ├── EPA/      (Environmental Protection Agency documents)
  └── index.txt (Master document index)

Required Documents:

CATEGORY 1 - OSHA (minimum 2 documents):
  Download PDF publications from www.osha.gov related to any of:
  - Fall protection or ladder safety
  - Electrical safety or lockout/tagout procedures
  - Personal protective equipment (PPE)
  - Hazard communication
  (Choose at least 2 topics and download one PDF per topic)

CATEGORY 2 - EPA (minimum 1 document):
  Download a PDF publication from www.epa.gov related to any of:
  - Indoor air quality in commercial buildings
  - Lead safety / renovation (RRP rule)
  - Refrigerant management (Section 608)
  - Asbestos safety
  (Choose at least 1 topic)

INDEX FILE (index.txt) must contain for each document:
  - Filename as saved in the library
  - Source URL where the document was obtained
  - Category (OSHA or EPA)
  - Brief description of the document content (1-2 sentences)
EOF
chown ga:ga /home/ga/Desktop/doc_requirements.txt
chmod 644 /home/ga/Desktop/doc_requirements.txt

# 4. Record task start timestamp (Anti-gaming)
date +%s > /tmp/task_start_time.txt

# 5. Launch Edge to a blank page
echo "Launching Microsoft Edge..."
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --password-store=basic \
    --start-maximized \
    about:blank > /tmp/edge.log 2>&1 &"

# Wait for Edge window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -iE "edge|microsoft"; then
        echo "Edge window detected"
        break
    fi
    sleep 1
done

# Focus Edge
DISPLAY=:1 wmctrl -a "Microsoft Edge" 2>/dev/null || true

# 6. Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="