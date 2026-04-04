#!/bin/bash
set -e
echo "=== Setting up annotate_pdf_highlight task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Clean up previous run artifacts
echo "Cleaning up..."
pkill -9 -f zotero 2>/dev/null || true
rm -f /home/ga/Documents/attention_paper.pdf
sleep 2

# 2. Seed Zotero library with papers
echo "Seeding library..."
# Using --mode ml to ensure 'Attention Is All You Need' is present
python3 /workspace/scripts/seed_library.py --mode ml > /tmp/seed_output.txt 2>&1

# 3. Generate the PDF file
# We use python + fpdf to generate a clean text-based PDF that Zotero can select text from
echo "Generating PDF..."

# Ensure fpdf is installed
if ! python3 -c "import fpdf" 2>/dev/null; then
    pip3 install fpdf --quiet
fi

cat > /tmp/generate_pdf.py << 'EOF'
from fpdf import FPDF
import os

pdf = FPDF()
pdf.add_page()
pdf.set_font("Arial", size=14)
pdf.cell(200, 10, txt="Attention Is All You Need", ln=1, align="C")
pdf.set_font("Arial", size=10)
pdf.cell(200, 10, txt="Vaswani et al., 2017", ln=1, align="C")
pdf.ln(10)

pdf.set_font("Arial", "B", 12)
pdf.cell(0, 10, "Abstract", ln=1)
pdf.set_font("Arial", "", 11)

text = """The dominant sequence transduction models are based on complex recurrent or convolutional neural networks that include an encoder and a decoder. The best performing models also connect the encoder and decoder through an attention mechanism. We propose a new simple network architecture, the Transformer, based solely on attention mechanisms, dispensing with recurrence and convolutions entirely. Experiments on two machine translation tasks show these models to be superior in quality while being more parallelizable and requiring significantly less time to train."""

pdf.multi_cell(0, 6, text)

output_path = "/home/ga/Documents/attention_paper.pdf"
os.makedirs(os.path.dirname(output_path), exist_ok=True)
pdf.output(output_path)
print(f"PDF generated at {output_path}")
EOF

python3 /tmp/generate_pdf.py
chown ga:ga /home/ga/Documents/attention_paper.pdf

# 4. Record task start time
date +%s > /tmp/task_start_time.txt

# 5. Start Zotero
echo "Starting Zotero..."
# Use setsid to detach from shell
sudo -u ga bash -c 'DISPLAY=:1 setsid /opt/zotero/zotero --no-remote > /home/ga/zotero.log 2>&1 &'

# 6. Wait for window and maximize
echo "Waiting for Zotero window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -q "Zotero"; then
        echo "Window found."
        break
    fi
    sleep 1
done

sleep 2
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true

# 7. Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="