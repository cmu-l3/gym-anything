#!/bin/bash
# Do NOT use set -e: draw.io startup commands may return non-zero

echo "=== Setting up ecommerce_sitemap_restructure task ==="

# Find draw.io binary
DRAWIO_BIN=""
if command -v drawio &>/dev/null; then
    DRAWIO_BIN="drawio"
elif [ -f /opt/drawio/drawio ]; then
    DRAWIO_BIN="/opt/drawio/drawio"
elif [ -f /usr/bin/drawio ]; then
    DRAWIO_BIN="/usr/bin/drawio"
fi

if [ -z "$DRAWIO_BIN" ]; then
    echo "ERROR: draw.io binary not found!"
    exit 1
fi

# Clean up any existing output files
rm -f /home/ga/Desktop/luma_sitemap.drawio 2>/dev/null || true
rm -f /home/ga/Desktop/luma_sitemap.png 2>/dev/null || true

# Create the Migration Specifications file
cat > /home/ga/Desktop/luma_migration_specs.txt << 'TEXTEOF'
LUMA E-COMMERCE MIGRATION SPECIFICATIONS
========================================
Project: Q3 Site Restructure
Date: 2026-03-02
Author: SEO Team

INSTRUCTIONS FOR DIAGRAMMING
----------------------------
Create a visual sitemap of the FUTURE STATE hierarchy.
Visual Coding Rules:
- UNCHANGED nodes: White/Default fill
- RENAMED nodes: Orange fill
- NEW nodes: Green fill
- REMOVED nodes: Do not include in the diagram

CURRENT STRUCTURE (Baseline)
----------------------------
Home
├── Women
│   ├── Tops
│   │   ├── Jackets
│   │   ├── Hoodies
│   │   ├── Tees
│   │   └── Tanks
│   └── Bottoms
│       ├── Pants
│       └── Shorts
├── Men
│   ├── Tops
│   │   ├── Jackets
│   │   ├── Hoodies
│   │   └── Tees
│   └── Bottoms
│       └── Pants
└── Gear
    ├── Bags
    └── Watches

FUTURE STATE CHANGES (Apply these to the diagram)
-------------------------------------------------
1. [RENAME] Men > Tops > 'Jackets' is changing to 'Outerwear'.
   (Reason: Keyword optimization. Color: ORANGE)

2. [NEW] New top-level category: 'Collections'.
   (Reason: Seasonal promotions. Color: GREEN)

3. [NEW] New subcategory under 'Collections': 'Eco-Friendly'.
   (Color: GREEN)

4. [NEW] New subcategory under 'Gear': 'Yoga'.
   (Color: GREEN)

5. [REMOVE] Women > Tops > 'Tanks' is being discontinued.
   (Reason: Low inventory. Do NOT include in diagram.)

6. All other categories remain UNCHANGED.

HIERARCHY SUMMARY FOR REFERENCE
-------------------------------
Home
 +-- Women (Unchanged)
      +-- Tops
           +-- Jackets (Unchanged)
           +-- Hoodies (Unchanged)
           +-- Tees (Unchanged)
      +-- Bottoms
           +-- Pants (Unchanged)
           +-- Shorts (Unchanged)
 +-- Men (Unchanged)
      +-- Tops
           +-- Outerwear (Renamed -> ORANGE)
           +-- Hoodies (Unchanged)
           +-- Tees (Unchanged)
      +-- Bottoms
           +-- Pants (Unchanged)
 +-- Gear (Unchanged)
      +-- Bags (Unchanged)
      +-- Watches (Unchanged)
      +-- Yoga (New -> GREEN)
 +-- Collections (New -> GREEN)
      +-- Eco-Friendly (New -> GREEN)
TEXTEOF

chown ga:ga /home/ga/Desktop/luma_migration_specs.txt 2>/dev/null || true

# Record baseline
echo "0" > /tmp/initial_drawio_count
date +%s > /tmp/task_start_timestamp

# Launch draw.io
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_sitemap.log 2>&1 &"

# Wait for draw.io window
echo "Waiting for draw.io window..."
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "draw.io"; then
        echo "draw.io window detected after ${i} seconds"
        break
    fi
    sleep 1
done

sleep 5
# Maximize window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss startup dialog (creates blank diagram)
echo "Dismissing startup dialog..."
DISPLAY=:1 xdotool key Escape
sleep 2

# Initial screenshot
DISPLAY=:1 import -window root /tmp/sitemap_task_start.png 2>/dev/null || true

echo "=== Setup complete ==="