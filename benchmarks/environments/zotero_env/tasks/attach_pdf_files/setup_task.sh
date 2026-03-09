#!/bin/bash
# Setup for attach_pdf_files task
set -u

echo "=== Setting up attach_pdf_files task ==="

DB="/home/ga/Zotero/zotero.sqlite"
PDF_DIR="/home/ga/Documents/PDFs"

# ── 1. Create PDF files ─────────────────────────────────────────────────────
echo "Generating PDF files..."
mkdir -p "$PDF_DIR"

# Helper to create a PDF with text
create_pdf() {
    local filename="$1"
    local title="$2"
    local text="$3"
    
    convert -size 612x792 xc:white \
        -font Helvetica -pointsize 24 -gravity North -annotate +0+50 "$title" \
        -pointsize 12 -gravity Center -annotate +0+0 "$text" \
        "$PDF_DIR/$filename"
}

create_pdf "vaswani2017_transformers.pdf" "Attention Is All You Need" "Vaswani et al. (2017)\nNeurIPS 30"
create_pdf "lecun2015_deep_learning_review.pdf" "Deep Learning" "LeCun, Bengio, Hinton (2015)\nNature 521"
create_pdf "krizhevsky2012_imagenet.pdf" "ImageNet Classification" "Krizhevsky et al. (2012)\nNeurIPS 25"
create_pdf "he2016_residual_learning.pdf" "Deep Residual Learning" "He et al. (2016)\nCVPR 2016"

chown -R ga:ga "$PDF_DIR"
echo "Created 4 PDFs in $PDF_DIR"

# ── 2. Stop Zotero & Seed Library ───────────────────────────────────────────
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 2

echo "Seeding library..."
# Seed standard library (classic + ML papers)
python3 /workspace/scripts/seed_library.py --mode all > /dev/null 2>&1

# ── 3. Record Baseline State ────────────────────────────────────────────────
# Record time for anti-gaming (sqlite uses unix epoch)
date +%s > /tmp/task_start_time

if [ -f "$DB" ]; then
    # Count existing PDF attachments (should be 0 after fresh seed, but good to check)
    INITIAL_ATTACHMENTS=$(sqlite3 "$DB" "SELECT COUNT(*) FROM itemAttachments WHERE contentType='application/pdf'" 2>/dev/null || echo "0")
    echo "$INITIAL_ATTACHMENTS" > /tmp/initial_attachment_count
else
    echo "0" > /tmp/initial_attachment_count
fi

# ── 4. Restart Zotero ───────────────────────────────────────────────────────
echo "Restarting Zotero..."
# Use setsid to detach from shell, running as user ga
sudo -u ga bash -c "DISPLAY=:1 setsid /opt/zotero/zotero --no-remote > /dev/null 2>&1 &"

# Wait for window
echo "Waiting for Zotero window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "zotero"; then
        echo "Window found."
        break
    fi
    sleep 1
done
sleep 5

# Maximize and Focus
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true

# ── 5. Capture Initial State ────────────────────────────────────────────────
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="