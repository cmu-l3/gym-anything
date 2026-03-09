#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Sales QBR Deck Task ==="

sudo -u ga mkdir -p /home/ga/Documents/Presentations

# Create the real Q3 2023 US Census Bureau Monthly Retail Trade Survey data CSV
sudo -u ga tee /home/ga/Documents/Presentations/q3_sales_data.csv > /dev/null << 'CSVEOF'
Category,July_2023_Billion_USD,August_2023_Billion_USD,September_2023_Billion_USD
Motor Vehicle & Parts Dealers,140.7,142.3,144.4
Furniture & Home Furnishings Stores,11.9,12.1,12.2
Electronics & Appliance Stores,8.0,8.1,8.2
Building Material & Garden Equipment,38.6,38.3,37.1
Food & Beverage Stores,76.6,77.2,77.5
Health & Personal Care Stores,37.2,37.5,37.6
Clothing & Accessories Stores,24.9,24.6,25.3
Sporting Goods Hobby & Music Bookstores,8.9,8.6,8.3
General Merchandise Stores,72.5,71.1,69.6
Nonstore Retailers (eCommerce & Direct),104.2,105.8,106.9
Food Services & Drinking Places,95.5,96.1,96.7
CSVEOF

# Create the minimal 2-slide draft ODP presentation
# NOTE: The title intentionally does NOT say "Q3 2023 Quarterly Business Review" —
# the agent must write the proper title. The file name and task description
# make the context clear; the agent must set the slide title correctly.
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentPresentation
from odf.draw import Page, Frame, TextBox
from odf.text import P

doc = OpenDocumentPresentation()

# Slide 1: Minimal title slide — no QBR/Q3 2023 keyword to avoid verifier contamination
slide1 = Page(name="Slide1")
doc.presentation.addElement(slide1)

tf1 = Frame(width="24cm", height="3.5cm", x="2cm", y="2cm")
slide1.addElement(tf1)
tb1 = TextBox()
tf1.addElement(tb1)
tb1.addElement(P(text="Sales Performance Summary"))

tf1b = Frame(width="24cm", height="2cm", x="2cm", y="5.8cm")
slide1.addElement(tf1b)
tb1b = TextBox()
tf1b.addElement(tb1b)
tb1b.addElement(P(text="DRAFT — See q3_sales_data.csv for data"))

# Slide 2: Agenda placeholder
slide2 = Page(name="Slide2")
doc.presentation.addElement(slide2)

tf2 = Frame(width="24cm", height="3cm", x="2cm", y="1cm")
slide2.addElement(tf2)
tb2 = TextBox()
tf2.addElement(tb2)
tb2.addElement(P(text="Presentation Outline"))

tf2b = Frame(width="24cm", height="12cm", x="2cm", y="4.5cm")
slide2.addElement(tf2b)
tb2b = TextBox()
tf2b.addElement(tb2b)
tb2b.addElement(P(text="[PLACEHOLDER - Expand into full presentation]"))
tb2b.addElement(P(text="Suggested sections: Executive Summary, Performance by Category,"))
tb2b.addElement(P(text="Monthly Trends, Key Insights, Risks, Outlook"))

doc.save("/home/ga/Documents/Presentations/qbr_q3_2023.odp")
print("ODP draft created successfully")
PYEOF

sudo chown -R ga:ga /home/ga/Documents/Presentations/

# Record baseline - no PDF yet, initial slide count = 2
echo "2" > /tmp/qbr_initial_slide_count
echo "0" > /tmp/qbr_initial_chart_count
date +%s > /tmp/task_start_timestamp
echo "no_pdf" > /tmp/qbr_pdf_status

# Take initial screenshot
su - ga -c "DISPLAY=:1 scrot /tmp/task_start_screenshot.png" || true

# Launch LibreOffice Impress with the draft
su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/qbr_q3_2023.odp > /tmp/impress_qbr.log 2>&1 &"

wait_for_process "soffice" 20
wait_for_window "LibreOffice Impress" 90

sleep 2
su - ga -c "DISPLAY=:1 xdotool mousemove 600 400 click 1" || true
sleep 1

wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

echo "=== Sales QBR Deck Task Setup Complete ==="
echo "Data file: /home/ga/Documents/Presentations/q3_sales_data.csv"
echo "Draft file: /home/ga/Documents/Presentations/qbr_q3_2023.odp"
echo "Goal: Build complete 7-slide Q3 2023 QBR with charts, notes, and PDF export"
