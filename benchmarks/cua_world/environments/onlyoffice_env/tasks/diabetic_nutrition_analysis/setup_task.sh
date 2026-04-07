#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Diabetic Nutrition Analysis Task ==="

# Record task start timestamp for anti-gaming checks
echo $(date +%s) > /tmp/diabetic_nutrition_analysis_start_ts

cleanup_temp_files
kill_onlyoffice ga
sleep 1

WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
DOCS_DIR="/home/ga/Documents"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Write ADA guidelines
cat > "$DOCS_DIR/ADA_guidelines.txt" << 'EOF'
AMERICAN DIABETES ASSOCIATION (ADA) DIETARY TARGETS
Patient Profile: 55-year-old Male, BMI 31 (Obese class I), Sedentary lifestyle
Condition: Type 2 Diabetes Mellitus

DAILY TARGETS:
- Calories: 1,800 - 2,200 kcal
- Carbohydrates: 200g - 275g total per day
- Protein: >= 70g
- Fiber: >= 25g
- Sodium: < 2,300mg

MEAL-LEVEL TARGETS:
- Carbohydrates per meal: <= 60g (Warning threshold)
EOF

# Create a deterministic Python script to generate realistic USDA and Food Diary datasets
cat > /tmp/generate_nutrition_data.py << 'PYEOF'
import csv
import json
import os

workspace_dir = "/home/ga/Documents/Spreadsheets"

nutrients = {
    "Oatmeal": [150, 5, 27, 3, 4, 0],
    "Scrambled Eggs": [140, 12, 2, 10, 0, 170],
    "Whole Wheat Bread": [80, 4, 15, 1, 2, 150],
    "Grilled Chicken Breast": [165, 31, 0, 3, 0, 74],
    "Brown Rice": [216, 5, 45, 2, 3, 10],
    "Broccoli": [55, 4, 11, 0, 5, 33],
    "Salmon Fillet": [208, 20, 0, 13, 0, 59],
    "Sweet Potato": [103, 2, 24, 0, 4, 41],
    "Greek Yogurt": [100, 17, 6, 0, 0, 36],
    "Apple": [95, 0, 25, 0, 4, 2],
    "Banana": [105, 1, 27, 0, 3, 1],
    "Pasta (Spaghetti)": [220, 8, 43, 1, 2, 1],
    "Marinara Sauce": [60, 2, 10, 2, 2, 350],
    "Cheddar Cheese": [113, 7, 1, 9, 0, 174],
    "Almonds": [164, 6, 6, 14, 3.5, 1],
    "Orange Juice": [112, 2, 26, 0, 0, 2],
    "Corn Tortilla": [52, 1, 11, 1, 1, 10],
    "Black Beans": [114, 8, 20, 0, 8, 1],
    "Avocado": [240, 3, 12, 22, 10, 11],
    "Ground Beef Patty": [250, 20, 0, 18, 0, 75],
    "White Rice": [205, 4, 45, 0, 1, 2],
    "Fried Chicken Thigh": [290, 14, 10, 21, 0, 400],
    "Coleslaw": [150, 1, 14, 10, 2, 200],
    "Biscuit": [250, 4, 30, 12, 1, 400],
    "Pepperoni Pizza": [298, 12, 34, 12, 2, 680],
    "Garden Salad": [20, 1, 4, 0, 2, 10],
    "Ranch Dressing": [140, 0, 2, 15, 0, 260],
    "Granola Bar": [190, 4, 29, 7, 2, 140],
    "Milk (2%)": [122, 8, 12, 5, 0, 100],
    "Coffee with Cream": [50, 1, 1, 5, 0, 15]
}

with open(os.path.join(workspace_dir, 'usda_nutrients.csv'), 'w') as f:
    writer = csv.writer(f)
    writer.writerow(['Food_Item', 'Calories_kcal', 'Protein_g', 'Carbs_g', 'Fat_g', 'Fiber_g', 'Sodium_mg'])
    for item, vals in nutrients.items():
        writer.writerow([item] + vals)

# The diet profile is realistic but has deliberate slip-ups resulting in high-carb / high-sodium events
diary = [
    ["Monday", "Breakfast", "Oatmeal", "1.5", "cup", 1.5],
    ["Monday", "Breakfast", "Banana", "1", "medium", 1],
    ["Monday", "Breakfast", "Coffee with Cream", "1", "cup", 1],
    ["Monday", "Lunch", "Grilled Chicken Breast", "1.5", "piece", 1.5],
    ["Monday", "Lunch", "Brown Rice", "1.5", "cup", 1.5],
    ["Monday", "Lunch", "Broccoli", "1", "cup", 1],
    ["Monday", "Dinner", "Salmon Fillet", "1", "fillet", 1],
    ["Monday", "Dinner", "Sweet Potato", "1", "medium", 1],
    ["Monday", "Dinner", "Avocado", "0.5", "medium", 0.5],
    ["Monday", "Snack", "Greek Yogurt", "1", "container", 1],
    ["Monday", "Snack", "Almonds", "1", "oz", 1],
    
    ["Tuesday", "Breakfast", "Scrambled Eggs", "2", "eggs", 2],
    ["Tuesday", "Breakfast", "Whole Wheat Bread", "2", "slices", 2],
    ["Tuesday", "Breakfast", "Orange Juice", "1", "cup", 1],
    ["Tuesday", "Lunch", "Garden Salad", "2", "cups", 1],
    ["Tuesday", "Lunch", "Ranch Dressing", "2", "tbsp", 1],
    ["Tuesday", "Lunch", "Grilled Chicken Breast", "1", "piece", 1],
    ["Tuesday", "Dinner", "Fried Chicken Thigh", "2", "pieces", 2],
    ["Tuesday", "Dinner", "Biscuit", "1", "piece", 1],
    ["Tuesday", "Dinner", "Coleslaw", "1", "cup", 1],
    ["Tuesday", "Snack", "Apple", "1", "medium", 1],
    ["Tuesday", "Snack", "Almonds", "1", "oz", 1],
    
    ["Wednesday", "Breakfast", "Oatmeal", "1", "cup", 1],
    ["Wednesday", "Breakfast", "Milk (2%)", "1", "cup", 1],
    ["Wednesday", "Lunch", "Pepperoni Pizza", "2", "slices", 2],
    ["Wednesday", "Lunch", "Orange Juice", "1", "cup", 1],
    ["Wednesday", "Dinner", "Ground Beef Patty", "1", "patty", 1],
    ["Wednesday", "Dinner", "Whole Wheat Bread", "2", "slices", 2],
    ["Wednesday", "Dinner", "Cheddar Cheese", "1", "slice", 1],
    ["Wednesday", "Dinner", "Garden Salad", "1", "cup", 0.5],
    ["Wednesday", "Snack", "Granola Bar", "1", "bar", 1],
    
    ["Thursday", "Breakfast", "Greek Yogurt", "1", "container", 1],
    ["Thursday", "Breakfast", "Banana", "1", "medium", 1],
    ["Thursday", "Breakfast", "Coffee with Cream", "1", "cup", 1],
    ["Thursday", "Lunch", "Salmon Fillet", "1", "fillet", 1],
    ["Thursday", "Lunch", "White Rice", "1", "cup", 1],
    ["Thursday", "Lunch", "Broccoli", "1", "cup", 1],
    ["Thursday", "Dinner", "Grilled Chicken Breast", "1", "piece", 1],
    ["Thursday", "Dinner", "Sweet Potato", "1", "medium", 1],
    ["Thursday", "Dinner", "Avocado", "0.5", "medium", 0.5],
    ["Thursday", "Snack", "Almonds", "1", "oz", 1],
    
    ["Friday", "Breakfast", "Scrambled Eggs", "2", "eggs", 2],
    ["Friday", "Breakfast", "Coffee with Cream", "2", "cups", 2],
    ["Friday", "Breakfast", "Apple", "1", "medium", 1],
    ["Friday", "Lunch", "Garden Salad", "2", "cups", 1],
    ["Friday", "Lunch", "Ranch Dressing", "1", "tbsp", 0.5],
    ["Friday", "Lunch", "Black Beans", "1", "cup", 1],
    ["Friday", "Dinner", "Pasta (Spaghetti)", "2.5", "cups", 2.5],
    ["Friday", "Dinner", "Marinara Sauce", "1.5", "cup", 1.5],
    ["Friday", "Dinner", "Cheddar Cheese", "1", "oz", 1],
    ["Friday", "Snack", "Granola Bar", "1", "bar", 1],
    
    ["Saturday", "Breakfast", "Biscuit", "2", "pieces", 2],
    ["Saturday", "Breakfast", "Scrambled Eggs", "1", "egg", 1],
    ["Saturday", "Breakfast", "Coffee with Cream", "1", "cup", 1],
    ["Saturday", "Lunch", "Pepperoni Pizza", "3", "slices", 3],
    ["Saturday", "Lunch", "Milk (2%)", "1", "cup", 1],
    ["Saturday", "Dinner", "Ground Beef Patty", "1", "patty", 1],
    ["Saturday", "Dinner", "White Rice", "1.5", "cup", 1.5],
    ["Saturday", "Dinner", "Broccoli", "1", "cup", 1],
    ["Saturday", "Snack", "Apple", "1", "medium", 1],
    
    ["Sunday", "Breakfast", "Oatmeal", "1.5", "cup", 1.5],
    ["Sunday", "Breakfast", "Banana", "1", "medium", 1],
    ["Sunday", "Lunch", "Corn Tortilla", "3", "tortillas", 3],
    ["Sunday", "Lunch", "Black Beans", "1.5", "cups", 1.5],
    ["Sunday", "Lunch", "Ground Beef Patty", "0.5", "patty", 0.5],
    ["Sunday", "Lunch", "Avocado", "0.5", "medium", 0.5],
    ["Sunday", "Dinner", "Grilled Chicken Breast", "1", "piece", 1],
    ["Sunday", "Dinner", "Brown Rice", "1", "cup", 1],
    ["Sunday", "Dinner", "Broccoli", "1", "cup", 1],
    ["Sunday", "Snack", "Almonds", "1", "oz", 1]
]

with open(os.path.join(workspace_dir, 'food_diary.csv'), 'w') as f:
    writer = csv.writer(f)
    writer.writerow(['Day', 'Meal', 'Food_Item', 'Portion_Size', 'Portion_Unit', 'Servings'])
    writer.writerows(diary)

# Pre-calculate ground truth totals to store for the verifier
daily_cals = {}
meal_carbs = {}
for day, meal, item, size, unit, servings in diary:
    cals = nutrients[item][0] * servings
    carbs = nutrients[item][2] * servings
    daily_cals[day] = daily_cals.get(day, 0) + cals
    meal_key = f"{day}_{meal}"
    meal_carbs[meal_key] = meal_carbs.get(meal_key, 0) + carbs

high_carb_meals = [{"day_meal": k, "carbs": v} for k, v in meal_carbs.items() if v > 60]

gt = {
    "daily_cals": list(daily_cals.values()),
    "high_carb_meals": high_carb_meals,
    "weekly_cals": sum(daily_cals.values())
}
# Output to /tmp so export_result.sh can capture it for verifier.py
with open("/tmp/nutrition_ground_truth.json", "w") as f:
    json.dump(gt, f)

PYEOF

python3 /tmp/generate_nutrition_data.py
chown -R ga:ga "$WORKSPACE_DIR"
chown ga:ga "$DOCS_DIR/ADA_guidelines.txt"

# Launch ONLYOFFICE with a blank spreadsheet
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors --new:cell > /tmp/onlyoffice.log 2>&1 &"

# Wait for window
wait_for_window "ONLYOFFICE" 30
focus_onlyoffice_window

# Maximize the window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/diabetic_nutrition_analysis_initial.png 2>/dev/null || true

echo "=== Setup complete ==="