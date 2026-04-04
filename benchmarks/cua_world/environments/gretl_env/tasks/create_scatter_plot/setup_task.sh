#!/bin/bash
echo "=== Setting up create_scatter_plot task ==="

source /workspace/scripts/task_utils.sh

setup_gretl_task "food.gdt" "scatter_plot"

echo ""
echo "============================================================"
echo "TASK: Create Scatter Plot in Gretl"
echo "============================================================"
echo ""
echo "Gretl is open with food.gdt loaded."
echo "Dataset: 40 households, variables: food_exp (weekly food"
echo "expenditure in dollars) and income (weekly income in \$100 units)."
echo ""
echo "Please:"
echo "1. Go to View > Graph specified vars > X-Y scatter"
echo "2. Select 'income' as the X variable"
echo "3. Select 'food_exp' as the Y variable"
echo "4. Click OK to create the scatter plot"
echo "5. In the graph window, save as PNG to:"
echo "   /home/ga/Documents/gretl_output/food_scatter.png"
echo "   (File > Save as in the graph window, choose PNG format)"
echo "============================================================"
