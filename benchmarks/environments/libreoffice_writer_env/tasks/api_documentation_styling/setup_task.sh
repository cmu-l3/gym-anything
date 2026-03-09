#!/bin/bash
set -e
echo "=== Setting up API Documentation Styling Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create Documents directory
sudo -u ga mkdir -p /home/ga/Documents

# Generate the raw ODT file using python and odfpy (available in env)
# We use Python to ensure we get a valid ODT structure without any existing fancy styles
echo "Generating draft document..."
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import H, P, Span
from odf import style

doc = OpenDocumentText()

# Create basic content
h1 = H(outline_level=1, text="Hyperion API v2 Reference")
doc.text.addElement(h1)

doc.text.addElement(P(text="Welcome to the Hyperion Analytics API. This interface allows you to programmatically access your data streams."))

# Authentication Section
doc.text.addElement(H(outline_level=2, text="Authentication"))
doc.text.addElement(P(text="All requests must include the Authorization header with your specific api_key. Failure to provide a valid key will result in a 403 Forbidden response."))

# Code Snippet 1 (JSON)
json_snippet_1 = """{
  "authenticated": true,
  "user": "admin_01",
  "scopes": ["read", "write", "analytics"],
  "expires_in": 3600
}"""
# Add as separate paragraphs to simulate raw text
for line in json_snippet_1.split('\n'):
    doc.text.addElement(P(text=line))

# Get User Profile Section
doc.text.addElement(H(outline_level=2, text="Get User Profile"))
doc.text.addElement(P(text="To retrieve the current user profile, send a GET request. Ensure the Content-Type header is set to application/json."))

# Code Snippet 2 (Python)
python_snippet = """import requests

def get_profile(api_key):
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json"
    }
    response = requests.get("https://api.hyperion.io/v2/me", headers=headers)
    return response.json()"""
for line in python_snippet.split('\n'):
    doc.text.addElement(P(text=line))

# Error Handling Section
doc.text.addElement(H(outline_level=2, text="Error Handling"))
doc.text.addElement(P(text="Successful requests return HTTP 200. If the api_key is missing, the server returns the following error object:"))

# Code Snippet 3 (JSON Error)
json_snippet_2 = """{
  "error": "unauthorized",
  "message": "Missing Authorization header",
  "code": 401
}"""
for line in json_snippet_2.split('\n'):
    doc.text.addElement(P(text=line))

doc.save("/home/ga/Documents/hyperion_api_draft.odt", addsuffix=False)
PYEOF

# Fix permissions
chown ga:ga /home/ga/Documents/hyperion_api_draft.odt
chmod 666 /home/ga/Documents/hyperion_api_draft.odt

# Launch LibreOffice Writer
echo "Launching LibreOffice Writer..."
if ! pgrep -f "soffice.bin" > /dev/null; then
    su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/hyperion_api_draft.odt > /tmp/writer.log 2>&1 &"
fi

# Wait for window
wait_for_window "LibreOffice Writer" 60 || wait_for_window "hyperion_api" 30

# Maximize and Focus
WID=$(get_writer_window_id)
if [ -n "$WID" ]; then
    echo "Focusing window $WID"
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    
    # Dismiss "Tip of the Day" or other popups if they appear
    sleep 2
    safe_xdotool ga :1 key Escape 2>/dev/null || true
fi

# Capture initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="