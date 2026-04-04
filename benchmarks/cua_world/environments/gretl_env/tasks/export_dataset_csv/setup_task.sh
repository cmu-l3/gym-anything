#!/bin/bash
echo "=== Setting up export_dataset_csv task ==="

source /workspace/scripts/task_utils.sh

setup_gretl_task "food.gdt" "export_csv"

echo ""
echo "============================================================"
echo "TASK: Export Dataset to CSV in Gretl"
echo "============================================================"
echo ""
echo "Gretl is open with food.gdt loaded."
echo "Dataset: 40 households, variables: food_exp and income."
echo ""
echo "Please:"
echo "1. Go to File > Save data as"
echo "2. Navigate to /home/ga/Documents/gretl_output/"
echo "3. Enter filename: food_data"
echo "4. Select file type: CSV (comma-separated values)"
echo "5. Click Save"
echo ""
echo "Expected output: /home/ga/Documents/gretl_output/food_data.csv"
echo "============================================================"
