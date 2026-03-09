#!/bin/bash
# Setup script for Import Products CSV task

echo "=== Setting up Import Products CSV Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Record initial product count
echo "Recording initial product count..."
INITIAL_COUNT=$(get_product_count 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_product_count
echo "Initial product count: $INITIAL_COUNT"

# Prepare the CSV file
CSV_DIR="/home/ga/Documents"
CSV_FILE="$CSV_DIR/craft_products_import.csv"
mkdir -p "$CSV_DIR"

echo "Creating CSV file at $CSV_FILE..."
cat > "$CSV_FILE" << 'EOF'
ID,Type,SKU,Name,Published,Is featured?,Visibility in catalog,Short description,Description,Regular price,Categories,Tags,Stock,Manage stock?
,simple,HMJ-RNG-001,"Handcrafted Sterling Silver Ring",1,0,visible,"Sterling silver artisan ring","Hand-forged sterling silver ring with hammered texture. Each piece is unique, made in our San Francisco studio.",45.00,Jewelry,"handmade,silver,artisan",25,1
,simple,HMP-TBL-002,"Ceramic Raku Tea Bowl",1,0,visible,"Traditional Raku tea bowl","Hand-fired Raku tea bowl with unique crackle glaze pattern. Perfect for tea ceremonies or as a display piece.",38.00,Pottery,"handmade,ceramic,raku",12,1
,simple,HMD-MWH-003,"Macramé Wall Hanging Large",1,0,visible,"Boho style macramé wall art","Large woven wall hanging made from 100% natural cotton cord on a driftwood branch.",65.00,Home Decor,"handmade,boho,decor",8,1
,simple,HMA-SCS-004,"Hand-Painted Silk Scarf",1,0,visible,"100% silk scarf, floral design","Luxurious hand-painted silk scarf featuring abstract floral motifs in blues and purples.",55.00,Accessories,"handmade,silk,fashion",15,1
,simple,HMP-DPS-005,"Stoneware Dinner Plate Set of 4",1,0,visible,"Durable stoneware plates","Set of 4 hand-thrown stoneware dinner plates with matte glaze finish. Dishwasher and microwave safe.",120.00,Pottery,"handmade,ceramic,dining",10,1
,simple,HMJ-NKL-006,"Beaded Turquoise Necklace",1,0,visible,"Genuine turquoise bead necklace","Strand of genuine turquoise beads with sterling silver clasp. 18 inch length.",72.00,Jewelry,"handmade,gemstone,jewelry",20,1
,simple,HMD-CTR-007,"Woven Cotton Table Runner",1,0,visible,"Hand-woven table runner","Blue and white patterned table runner, hand-woven on a traditional loom. 14x72 inches.",48.00,Home Decor,"handmade,textile,dining",18,1
,simple,HMP-VAS-008,"Hand-Thrown Ceramic Vase",1,0,visible,"Tall ceramic vase","Elegant tall vase for long-stemmed flowers. Glazed in a deep ocean blue.",85.00,Pottery,"handmade,ceramic,decor",6,1
EOF

chown ga:ga "$CSV_FILE"
chmod 644 "$CSV_FILE"

# CRITICAL: Ensure WordPress admin page is showing
echo "Ensuring WordPress admin page is displayed..."
if ! ensure_wordpress_shown 60; then
    echo "FATAL: Could not load WordPress admin page - task cannot proceed"
    exit 1
fi
echo "WordPress admin page confirmed loaded"

# Focus and maximize Firefox window
echo "Focusing Firefox window..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "CSV file ready at: $CSV_FILE"