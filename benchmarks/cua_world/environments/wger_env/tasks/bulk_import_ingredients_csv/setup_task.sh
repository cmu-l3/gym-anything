#!/bin/bash
echo "=== Setting up bulk_import_ingredients_csv task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure wger is running and ready
wait_for_wger_page

# Get initial count of ingredients
echo "Querying initial ingredient count..."
INITIAL_COUNT=$(docker exec wger-web python3 manage.py shell -c "from wger.nutrition.models import Ingredient; print(Ingredient.objects.count())" 2>/dev/null | tail -n 1 | tr -d '\r')
if ! [[ "$INITIAL_COUNT" =~ ^[0-9]+$ ]]; then
    INITIAL_COUNT="0"
fi
echo "$INITIAL_COUNT" > /tmp/initial_count.txt
echo "Initial ingredient count: $INITIAL_COUNT"

# Create the target CSV file for the agent
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/supplier_ingredients.csv << 'EOF'
Name,Energy_kcal,Protein_g,Carbs_g,Fat_g
Bulk Whey Protein Isolate,377.0,90.0,1.5,1.0
Organic Rolled Oats,379.0,13.0,68.0,6.5
Premium Almond Butter,614.0,21.0,19.0,50.0
Chia Seeds,486.0,17.0,42.0,31.0
Brown Rice,360.0,8.0,78.0,3.0
Lentils,353.0,26.0,60.0,1.0
Quinoa,368.0,14.0,64.0,6.0
Flaxseed Meal,534.0,18.0,29.0,42.0
Pea Protein Powder,380.0,80.0,3.0,6.0
Hemp Hearts,553.0,31.0,5.0,49.0
Dried Chickpeas,364.0,19.0,61.0,6.0
Pumpkin Seeds,559.0,30.0,11.0,49.0
EOF

chown ga:ga /home/ga/Documents/supplier_ingredients.csv
chmod 644 /home/ga/Documents/supplier_ingredients.csv

# Launch Firefox to the wger ingredient overview page
launch_firefox_to "http://localhost/en/ingredient/overview/" 5

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="