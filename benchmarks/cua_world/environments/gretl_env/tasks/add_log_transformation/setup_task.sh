#!/bin/bash
echo "=== Setting up add_log_transformation task ==="

source /workspace/scripts/task_utils.sh

setup_gretl_task "food.gdt" "log_transformation"

echo ""
echo "============================================================"
echo "TASK: Add Log Transformation of food_exp in Gretl"
echo "============================================================"
echo ""
echo "Gretl is open with food.gdt loaded."
echo "Dataset: 40 households, variables: food_exp and income."
echo ""
echo "Please:"
echo "1. Click on 'food_exp' in the variable list to select it"
echo "2. Go to Add > Logs of selected variables"
echo "   This will create 'l_food_exp' (natural log of food_exp)"
echo "3. Verify that 'l_food_exp' appears in the variable list"
echo "4. Save the modified dataset to:"
echo "   /home/ga/Documents/gretl_output/food_with_log.gdt"
echo "   (File > Save data as, choose .gdt format)"
echo "============================================================"
