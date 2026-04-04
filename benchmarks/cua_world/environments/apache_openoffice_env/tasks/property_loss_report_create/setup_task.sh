#!/bin/bash
# Setup script for Property Loss Report task
set -e

echo "=== Setting up Property Loss Report Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Prepare Directories
sudo -u ga mkdir -p /home/ga/Documents/site_photos
rm -f /home/ga/Documents/Claim_778492_Report.odt 2>/dev/null || true

# 2. Create Claim Data JSON
cat > /home/ga/Documents/claim_data.json << 'EOF'
{
  "carrier": "Apex Mutual Insurance",
  "claim_number": "778492",
  "policy_number": "HO-998-221-00",
  "date_of_loss": "2026-02-12",
  "insured": {
    "name": "Robert & Sarah Miller",
    "address": "2409 Oak Creek Dr, Austin, TX 78704"
  },
  "narrative": "Insured reported water damage in the master bathroom. Inspection reveals a failure of the braided steel supply line to the vanity sink. Water migrated from the bathroom into the adjacent hallway and master bedroom. The supply line has been replaced by an emergency plumber. This report details the cosmetic repairs required for the bathroom vanity, drywall, and laminate flooring.",
  "repairs": [
    {"item": "Detach and reset vanity cabinet", "qty": "1.0 EA", "unit_cost": "250.00", "total": "250.00"},
    {"item": "Replace 1/2\" Drywall (wet area)", "qty": "64.0 SF", "unit_cost": "2.10", "total": "134.40"},
    {"item": "Paint walls (2 coats)", "qty": "320.0 SF", "unit_cost": "0.85", "total": "272.00"},
    {"item": "Replace Laminate Flooring", "qty": "145.0 SF", "unit_cost": "4.50", "total": "652.50"},
    {"item": "Replace Baseboards", "qty": "45.0 LF", "unit_cost": "3.00", "total": "135.00"}
  ],
  "grand_total": "1,443.90",
  "photos": [
    {"file": "IMG_001.jpg", "caption": "Figure 1: Failed supply line under master bath sink."},
    {"file": "IMG_002.jpg", "caption": "Figure 2: Water damage to drywall behind vanity."},
    {"file": "IMG_003.jpg", "caption": "Figure 3: Affected laminate flooring in adjacent hallway."}
  ]
}
EOF
chown ga:ga /home/ga/Documents/claim_data.json

# 3. Generate Dummy Photos (using Python PIL to ensure no external dependency issues)
# We create 3 distinct colored images with text to simulate photos
python3 << 'PYEOF'
from PIL import Image, ImageDraw, ImageFont
import os

photo_dir = "/home/ga/Documents/site_photos"
photos = [
    ("IMG_001.jpg", "Supply Line Failure", (200, 100, 100)),
    ("IMG_002.jpg", "Drywall Damage", (100, 200, 100)),
    ("IMG_003.jpg", "Flooring Damage", (100, 100, 200))
]

try:
    for filename, text, color in photos:
        img = Image.new('RGB', (640, 480), color=color)
        d = ImageDraw.Draw(img)
        # Draw some "content" (lines)
        d.line((0, 0, 640, 480), fill=(255, 255, 255), width=5)
        d.line((0, 480, 640, 0), fill=(255, 255, 255), width=5)
        # Save
        path = os.path.join(photo_dir, filename)
        img.save(path, quality=80)
        print(f"Created {path}")
except ImportError:
    # Fallback if PIL not installed (though env specifies python packages)
    # Use convert or just empty files if strictly necessary, but PIL should be there
    print("PIL not found, trying imagemagick or creating placeholders")
    import subprocess
    for filename, _, _ in photos:
         path = os.path.join(photo_dir, filename)
         subprocess.run(["convert", "-size", "640x480", "xc:gray", path], check=False)

PYEOF
chown -R ga:ga /home/ga/Documents/site_photos

# 4. Ensure OpenOffice is ready (shortcut on desktop)
mkdir -p /home/ga/Desktop
if [ -f "/usr/share/applications/openoffice4-writer.desktop" ]; then
    cp "/usr/share/applications/openoffice4-writer.desktop" /home/ga/Desktop/
    chmod +x /home/ga/Desktop/openoffice4-writer.desktop
    chown ga:ga /home/ga/Desktop/openoffice4-writer.desktop
fi

# 5. Record Start Time
date +%s > /tmp/task_start_time.txt

# 6. Take Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="