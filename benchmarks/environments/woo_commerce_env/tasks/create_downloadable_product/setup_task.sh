#!/bin/bash
# Setup script for Create Downloadable Product task

echo "=== Setting up Create Downloadable Product Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time and initial product count
date +%s > /tmp/task_start_time
INITIAL_COUNT=$(get_product_count 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_product_count
echo "Initial product count: $INITIAL_COUNT"

# 2. Generate the PDF file to be uploaded
echo "Generating sample PDF file..."
mkdir -p /home/ga/Documents
PDF_PATH="/home/ga/Documents/vintage_floral_pattern.pdf"

# Create a minimal valid PDF content to ensure upload works smoothly
cat > "$PDF_PATH" << 'EOF'
%PDF-1.4
1 0 obj <</Type /Catalog /Pages 2 0 R>> endobj
2 0 obj <</Type /Pages /Kids [3 0 R] /Count 1>> endobj
3 0 obj <</Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R>> endobj
4 0 obj <</Length 55>> stream
BT /F1 24 Tf 100 700 Td (Vintage Floral Cross-Stitch Pattern) Tj ET
endstream
endobj
xref
0 5
0000000000 65535 f
0000000010 00000 n
0000000060 00000 n
0000000117 00000 n
0000000206 00000 n
trailer <</Size 5 /Root 1 0 R>>
startxref
311
%%EOF

# Set permissions
chown ga:ga "$PDF_PATH"
chmod 644 "$PDF_PATH"
echo "Created PDF at $PDF_PATH"

# 3. Ensure WordPress admin is loaded
echo "Ensuring WordPress admin page is displayed..."
if ! ensure_wordpress_shown 60; then
    echo "FATAL: Could not load WordPress admin page."
    exit 1
fi

# 4. Navigate to Products page to start fresh
# We'll rely on the agent to click "Add New", but starting on the Products list is helpful
echo "Navigating to Products list..."
su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/edit.php?post_type=product' &"
sleep 5

# 5. Focus and maximize
echo "Focusing Firefox..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 6. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="