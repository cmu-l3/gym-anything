#!/bin/bash
set -e
echo "=== Setting up structure_req_hierarchy task ==="

source /workspace/scripts/task_utils.sh

# 1. Kill any running ReqView instances
pkill -f "reqview" 2>/dev/null || true
sleep 2

# 2. Prepare Project Directory
PROJECT_DIR="/home/ga/Documents/ReqView/structure_req_project"
DOCS_DIR="$PROJECT_DIR/documents"

rm -rf "$PROJECT_DIR"
mkdir -p "$DOCS_DIR"

# 3. Create project.json
cat > "$PROJECT_DIR/project.json" << EOF
{
  "id": "structure_req_project",
  "name": "Migration Project",
  "documents": [
    {
      "id": "IMP",
      "name": "Imported Specs",
      "file": "documents/IMP.json"
    }
  ],
  "nextDocId": 2
}
EOF

# 4. Create IMP.json with FLAT structure (all items at root level)
# IDs are simple integers here, ReqView prepends the doc ID (IMP) in the UI.
cat > "$DOCS_DIR/IMP.json" << EOF
{
  "docId": "IMP",
  "name": "Imported Specs",
  "lastId": 6,
  "data": [
    {
      "id": "1",
      "heading": "User Authentication",
      "text": "Section for user auth requirements"
    },
    {
      "id": "2",
      "text": "The system shall allow login via email."
    },
    {
      "id": "3",
      "text": "The system shall support 2FA."
    },
    {
      "id": "4",
      "text": "The system shall enforce password complexity."
    },
    {
      "id": "5",
      "heading": "Data Export",
      "text": "Section for export requirements"
    },
    {
      "id": "6",
      "text": "The system shall export to CSV."
    }
  ]
}
EOF

# Set permissions
chown -R ga:ga "/home/ga/Documents/ReqView"

# 5. Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 6. Launch ReqView
echo "Launching ReqView..."
launch_reqview_with_project "$PROJECT_DIR"

# 7. Open the specific document "Imported Specs"
# In the project tree, "Imported Specs" will be the only doc.
# Coordinates for top item in tree are roughly 114, 415 (based on open_srs_document utils)
# We'll try to click it to ensure it's open.
sleep 5
echo "Opening Imported Specs document..."
DISPLAY=:1 xdotool mousemove 100 400 click 1 2>/dev/null || true
sleep 2

# 8. Maximize and Capture Initial State
maximize_window
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="