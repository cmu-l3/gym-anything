#!/bin/bash
# Export results for advanced_workforce_analytics task

set -e

echo "=== Exporting Advanced Workforce Analytics Results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/workforce_analytics_final_screenshot.png

echo "[1/3] Reading ground truth and report file..."
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

python3 << PYEOF
import json
import os
import re

result = {
    "task_start_timestamp": int("${TASK_START}"),
    "report_file_exists": False,
    "report_file_size": 0,
    "report_content": "",
    "report_line_count": 0,
    "has_q1_label": False,
    "has_q2_label": False,
    "has_q3_label": False,
    "has_q4_label": False,
    "extracted_q1_city": None,
    "extracted_q1_salary": None,
    "extracted_q2_manager": None,
    "extracted_q2_count": None,
    "extracted_q3_pct": None,
    "extracted_q4_title": None,
    "ground_truth": {}
}

# Load ground truth from setup
try:
    with open("/tmp/workforce_analytics_ground_truth.json") as f:
        result["ground_truth"] = json.load(f)
except Exception as e:
    result["ground_truth_error"] = str(e)

# Read the report file
report_path = "/home/ga/Desktop/workforce_analytics_report.txt"
if os.path.exists(report_path):
    result["report_file_exists"] = True
    result["report_file_size"] = os.path.getsize(report_path)
    try:
        with open(report_path, "r") as f:
            content = f.read()
        result["report_content"] = content[:4000]
        result["report_line_count"] = len([l for l in content.splitlines() if l.strip()])

        content_upper = content.upper()
        result["has_q1_label"] = "Q1" in content_upper
        result["has_q2_label"] = "Q2" in content_upper
        result["has_q3_label"] = "Q3" in content_upper
        result["has_q4_label"] = "Q4" in content_upper

        # Extract Q1: city and salary
        # Look for lines near Q1 for city names and numbers
        lines = content.splitlines()
        for i, line in enumerate(lines):
            if "Q1" in line.upper():
                # Scan next 5 lines for city name and salary
                context = " ".join(lines[i:i+6])
                # Look for known city names from HR schema
                cities = ["Seattle", "Toronto", "London", "Munich", "Oxford", "Southlake",
                          "South San Francisco", "South Brunswick", "Venice", "Tokyo",
                          "Singapore", "Sydney", "Mexico City", "Bombay"]
                for city in cities:
                    if city.lower() in context.lower():
                        result["extracted_q1_city"] = city
                        break
                # Look for salary number (4-6 digits possibly with decimal)
                nums = re.findall(r'\b(\d{4,6}(?:\.\d{1,2})?)\b', context)
                if nums:
                    result["extracted_q1_salary"] = float(nums[0])
                break

        # Extract Q2: manager name
        for i, line in enumerate(lines):
            if "Q2" in line.upper():
                context = " ".join(lines[i:i+6])
                # Look for known manager names
                managers = ["Steven King", "Neena Kochhar", "Lex De Haan",
                            "Michael Hartstein", "Hermann Baer", "Shelley Higgins",
                            "William Gietz", "Nancy Greenberg", "Daniel Faviet"]
                for mgr in managers:
                    if mgr.lower() in context.lower():
                        result["extracted_q2_manager"] = mgr
                        break
                # Extract count number
                nums = re.findall(r'\b(\d{1,3})\b', context)
                if nums:
                    result["extracted_q2_count"] = int(nums[0])
                break

        # Extract Q3: percentage
        for i, line in enumerate(lines):
            if "Q3" in line.upper():
                context = " ".join(lines[i:i+6])
                nums = re.findall(r'(-?\d+(?:\.\d{1,2})?)\s*%?', context)
                if nums:
                    result["extracted_q3_pct"] = float(nums[0])
                break

        # Extract Q4: job title
        for i, line in enumerate(lines):
            if "Q4" in line.upper():
                context = " ".join(lines[i:i+6])
                # Look for known job titles
                job_titles = ["Stock Clerk", "Sales Representative", "Sales Manager",
                              "Programmer", "Shipping Clerk", "Finance Manager",
                              "Accountant", "Administration Assistant", "IT Programmer",
                              "Human Resources Representative", "Marketing Manager"]
                for title in job_titles:
                    if title.lower() in context.lower():
                        result["extracted_q4_title"] = title
                        break
                break

    except Exception as e:
        result["read_error"] = str(e)[:200]

with open("/tmp/advanced_workforce_analytics_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps({
    "file_exists": result["report_file_exists"],
    "labels": [result["has_q1_label"], result["has_q2_label"],
               result["has_q3_label"], result["has_q4_label"]],
    "extracted": {
        "q1_city": result["extracted_q1_city"],
        "q2_manager": result["extracted_q2_manager"],
        "q3_pct": result["extracted_q3_pct"],
        "q4_title": result["extracted_q4_title"]
    }
}, indent=2))
PYEOF

echo "[2/3] Validating result JSON..."
python3 -m json.tool /tmp/advanced_workforce_analytics_result.json > /dev/null && echo "  Result JSON valid"

echo "=== Export Complete ==="
echo "  Results saved to: /tmp/advanced_workforce_analytics_result.json"
