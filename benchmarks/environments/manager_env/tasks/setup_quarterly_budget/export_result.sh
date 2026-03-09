#!/bin/bash
echo "=== Exporting setup_quarterly_budget result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# -----------------------------------------------------------------------
# Python script to scrape Manager.io for result validation
# -----------------------------------------------------------------------
python3 -c '
import requests
import re
import json
import sys

BASE_URL = "http://localhost:8080"
OUTPUT_FILE = "/tmp/task_result.json"

result = {
    "budgets_enabled": False,
    "budget_found": False,
    "budget_name": None,
    "line_items": {},
    "task_start": int(sys.argv[1]),
    "task_end": int(sys.argv[2])
}

try:
    s = requests.Session()
    # Login
    s.post(f"{BASE_URL}/login", data={"Username": "administrator"}, allow_redirects=True)

    # Get Business Key
    biz_page = s.get(f"{BASE_URL}/businesses").text
    m = re.search(r"start\?([^\"&\s]+)[^<]{0,300}Northwind Traders", biz_page)
    if not m:
        raise Exception("Northwind Traders business not found")
    biz_key = m.group(1)

    # 1. Check if Budgets module is enabled
    # We check the Summary page or the sidebar for the "Budgets" link
    summary_page = s.get(f"{BASE_URL}/summary?{biz_key}").text
    if "Budgets" in summary_page and "/budgets?" in summary_page:
        result["budgets_enabled"] = True

    # 2. Check for the specific budget
    if result["budgets_enabled"]:
        budgets_page = s.get(f"{BASE_URL}/budgets?{biz_key}").text
        
        # Look for "Q1 2025 Operating Budget" link
        # Regex to capture the View/Edit key
        # Link format: <a href="budget-view?Key=...">Q1 2025 Operating Budget</a>
        budget_match = re.search(r"href=\"(budget-view\?Key=[^&\"]+)[^>]*>Q1 2025 Operating Budget", budgets_page)
        
        if budget_match:
            result["budget_found"] = True
            result["budget_name"] = "Q1 2025 Operating Budget"
            view_url = budget_match.group(1)
            
            # Fetch budget details
            # We might need to go to the Edit screen to parse values easily, or parse the View screen
            # Edit screen is often structurally cleaner for values
            edit_url = view_url.replace("budget-view", "budget-form")
            edit_page = s.get(f"{BASE_URL}/{edit_url}").text
            
            # Parse line items
            # This is tricky without a DOM parser, but Manager forms usually have Javascript objects or inputs
            # We will look for account names and nearby amounts in the HTML text
            
            # Simple heuristic: Split by rows or look for patterns like "Sales" ... "135000"
            # Since HTML parsing is fragile with regex, we try to be robust
            
            # Target accounts to check
            targets = ["Sales", "Cost of sales", "Rent", "Wages and salaries"]
            
            for account in targets:
                # Regex to find the account name followed eventually by a value
                # This is an approximation. In a real DOM it would be safer.
                # Manager inputs often look like value="135000"
                
                # Check if account is present
                if account in edit_page:
                    # Try to find the amount associated. In the form, the account is a select/text, 
                    # and the amount is an input later in the row.
                    # We will dump the "clean" text of the page to simple regex
                    
                    # Pattern: AccountName ... value="123456"
                    # We accept that this might be noisy.
                    
                    # Alternative: Extract all input values and map them
                    pass 

            # Since precise scraping of a complex dynamic form with regex is hard, 
            # let us rely on the View page which usually renders a table.
            view_page = s.get(f"{BASE_URL}/{view_url}").text
            
            # The view page displays a table. We can look for the row with the account name and the total.
            # Example row: <td>Sales</td> ... <td ...>135,000.00</td>
            
            for account in targets:
                # Find the account name
                # Then look for the number in the vicinity
                # Remove newlines for easier regex
                clean_view = view_page.replace("\n", " ")
                
                # Regex: Account Name ... (some tags) ... Number
                # Manager formats numbers with commas: 135,000.00
                pattern = re.escape(account) + r".{1,300}?([0-9,]+\.[0-9]{2})"
                match = re.search(pattern, clean_view)
                if match:
                    amount_str = match.group(1).replace(",", "")
                    try:
                        result["line_items"][account] = float(amount_str)
                    except:
                        pass
        
except Exception as e:
    result["error"] = str(e)

with open(OUTPUT_FILE, "w") as f:
    json.dump(result, f, indent=2)

' "$TASK_START" "$TASK_END"

# Export result
if [ -f /tmp/task_result.json ]; then
    echo "Export successful"
    cat /tmp/task_result.json
else
    echo "Export failed: No result file generated"
fi