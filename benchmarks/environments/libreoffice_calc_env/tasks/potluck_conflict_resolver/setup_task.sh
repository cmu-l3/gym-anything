#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Potluck Conflict Resolver Task ==="

# Create Documents directory
sudo -u ga mkdir -p /home/ga/Documents

# Create CSV file with potluck sign-ups (including seeded problems)
cat > /home/ga/Documents/potluck_signups.csv << 'CSVEOF'
Name,Dish,Category,Servings,Ingredients
Sarah Martinez,Chocolate Chip Cookies,Dessert,24,flour sugar butter chocolate chips eggs vanilla
Mike Thompson,Oatmeal Cookies,Dessert,20,oats flour butter brown sugar eggs cinnamon raisins
Jennifer Lee,Veggie Platter,Appetizer,30,carrots celery peppers cherry tomatoes hummus ranch dip
David Kim,Thai Peanut Noodles,Main,15,rice noodles peanut sauce vegetables tofu sesame oil
Rachel Brown,Green Salad,Side,25,mixed lettuce tomatoes cucumbers red onion balsamic vinaigrette
Tom Harris,Brownies,Dessert,18,chocolate flour butter sugar eggs cocoa powder
Lisa Patel,Fruit Salad,Dessert,20,strawberries grapes melon pineapple blueberries
Kevin Rodriguez,BBQ Chicken Wings,Main,30,chicken wings BBQ sauce garlic powder onion powder
Amanda Stone,Deviled Eggs,Appetizer,24,eggs mayonnaise mustard paprika salt pepper
Chris Johnson,Mac and Cheese,Side,20,elbow pasta cheddar cheese milk butter breadcrumbs
Nicole Foster,Peanut Butter Brownies,Dessert,16,peanut butter chocolate flour eggs butter sugar
Mark Wilson,Caesar Salad,Side,18,romaine lettuce parmesan cheese croutons caesar dressing
Emily Davis,Spinach Artichoke Dip,Appetizer,12,spinach artichokes cream cheese sour cream mayo
Brian Lewis,Pulled Pork,Main,25,pork shoulder BBQ sauce brown sugar apple cider vinegar
Jessica Miller,Sugar Cookies,Dessert,30,flour sugar butter eggs vanilla almond extract
CSVEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/potluck_signups.csv
sudo chmod 644 /home/ga/Documents/potluck_signups.csv

echo "✅ Created potluck_signups.csv with 15 sign-ups"
echo "   - 6 Desserts (40% - imbalanced)"
echo "   - 3 Cookie dishes (duplicates in Dessert category)"
echo "   - 2 Dishes with peanut/peanut butter (allergen concerns)"
echo "   - Total: 327 servings for 40 people (~8.2 per person)"

# Launch LibreOffice Calc with blank spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore > /tmp/calc_potluck_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_potluck_task.log || true
    # Don't exit, continue anyway
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # Don't exit, continue anyway
fi

# Click on center of the screen to select current desktop
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Calc window
echo "Focusing Calc window..."
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    if focus_window "$wid"; then
        echo "✅ Calc window focused"
        # Maximize window
        safe_xdotool ga :1 key F11
        sleep 0.5
    fi
fi

echo ""
echo "=== Potluck Conflict Resolver Task Setup Complete ==="
echo ""
echo "📋 TASK INSTRUCTIONS:"
echo "═══════════════════════════════════════════════════════════════"
echo "You are coordinating a 40-person neighborhood potluck."
echo "The sign-up sheet has problems you need to identify and flag."
echo ""
echo "REQUIRED ACTIONS:"
echo ""
echo "1️⃣  IMPORT DATA"
echo "   • Open /home/ga/Documents/potluck_signups.csv"
echo "   • File → Open → Select CSV file"
echo ""
echo "2️⃣  ADD DUPLICATE DETECTION (Column F or later)"
echo "   • Create header: 'Duplicate Alert'"
echo "   • Formula: =IF(COUNTIF(\$C:\$C,C2)>1,\"CHECK: Multiple\",\"\")"
echo "   • Copy formula down to all data rows"
echo ""
echo "3️⃣  CALCULATE SERVINGS"
echo "   • Sum total servings: =SUM(D:D)"
echo "   • Calculate per-person: =(total)/40"
echo ""
echo "4️⃣  FLAG ALLERGENS (Column G or later)"
echo "   • Create header: 'Allergen Alert'"
echo "   • Formula: =IF(OR(ISNUMBER(SEARCH(\"peanut\",E2)),ISNUMBER(SEARCH(\"nut\",E2))),\"⚠ PEANUT\",\"\")"
echo "   • Apply conditional formatting (red background)"
echo ""
echo "5️⃣  CREATE CATEGORY SUMMARY"
echo "   • Use COUNTIF to count each category"
echo "   • Appetizer: =COUNTIF(C:C,\"Appetizer\")"
echo "   • Main: =COUNTIF(C:C,\"Main\")"
echo "   • Side: =COUNTIF(C:C,\"Side\")"
echo "   • Dessert: =COUNTIF(C:C,\"Dessert\")"
echo ""
echo "💾 File will be auto-saved as potluck_analysis.ods"
echo "═══════════════════════════════════════════════════════════════"