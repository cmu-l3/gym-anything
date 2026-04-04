#!/usr/bin/env python3
"""
Verifier for document_menu_inventory task.

This verifier checks if the agent successfully navigated the POS Back Office
and created an accurate inventory report matching the database ground truth.

Criteria:
1. Report file exists and was created during the task.
2. Contains correct menu categories and item counts.
3. Identifies correct total item count.
4. Identifies most and least expensive items.
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_document_menu_inventory(traj, env_info, task_info):
    """
    Verify the menu inventory report against ground truth from DB.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check basic existence
    if not result.get("output_exists", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Report file ~/menu_inventory_report.txt was not created."
        }

    if not result.get("created_during_task", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Report file exists but timestamp indicates it was not created during this task session."
        }

    score = 10
    feedback_parts = ["File created (+10)"]

    # 3. Retrieve Report and Ground Truth content
    agent_report_content = ""
    ground_truth_content = ""

    # Get Agent Report
    try:
        temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        copy_from_env(result["report_path"], temp_report.name)
        with open(temp_report.name, 'r', errors='ignore') as f:
            agent_report_content = f.read()
        os.unlink(temp_report.name)
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"File exists but could not be read: {e}"}

    # Get Ground Truth
    try:
        temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        copy_from_env(result["ground_truth_path"], temp_gt.name)
        with open(temp_gt.name, 'r', errors='ignore') as f:
            ground_truth_content = f.read()
        os.unlink(temp_gt.name)
    except Exception:
        # If ground truth failed to generate (e.g. DB locked), we rely on VLM or manual check
        # But for this implementation, we fail safe
        return {
            "passed": False, 
            "score": score, 
            "feedback": "Verification failed: Could not retrieve ground truth from system."
        }

    # Normalize content for matching
    report_upper = agent_report_content.upper()
    
    # 4. Parse Ground Truth
    # Format: CATEGORY:Name:Count or TOTAL:Count or MOST_EXPENSIVE:Name:Price
    gt_categories = {}
    gt_total = 0
    gt_most_exp = None
    gt_least_exp = None

    for line in ground_truth_content.splitlines():
        parts = line.strip().split(':')
        if not parts or len(parts) < 2: 
            continue
            
        key = parts[0]
        if key == "CATEGORY":
            gt_categories[parts[1].upper()] = int(parts[2])
        elif key == "TOTAL":
            gt_total = int(parts[1])
        elif key == "MOST_EXPENSIVE":
            gt_most_exp = {"name": parts[1].upper(), "price": float(parts[2])}
        elif key == "LEAST_EXPENSIVE":
            gt_least_exp = {"name": parts[1].upper(), "price": float(parts[2])}

    # 5. Verify Categories (20 pts)
    # Check if category names appear in report
    cats_found = 0
    total_cats = len(gt_categories)
    
    if total_cats > 0:
        for cat_name in gt_categories:
            if cat_name in report_upper:
                cats_found += 1
        
        cat_score = int(20 * (cats_found / total_cats))
        score += cat_score
        feedback_parts.append(f"Categories found: {cats_found}/{total_cats} (+{cat_score})")

    # 6. Verify Counts (25 pts)
    # Check if the correct count appears near the category name
    counts_correct = 0
    if total_cats > 0:
        for cat_name, count in gt_categories.items():
            # Regex to find Category Name followed by Count within a reasonable distance
            # e.g. "Beverages: 5" or "Beverages - 5 items"
            # We look for the number 'count' in the same line or context as 'cat_name'
            # Simple heuristic: Split report into lines, find line with cat_name, check if it has count
            for line in report_upper.splitlines():
                if cat_name in line:
                    # check for the number as a word boundary to avoid partial matches (e.g. 1 in 15)
                    if re.search(r'\b' + str(count) + r'\b', line):
                        counts_correct += 1
                        break
        
        count_score = int(25 * (counts_correct / total_cats))
        score += count_score
        feedback_parts.append(f"Counts correct: {counts_correct}/{total_cats} (+{count_score})")

    # 7. Verify Total (15 pts)
    # Look for the total number explicitly mentioned with "Total"
    total_found = False
    total_matches = re.findall(r'TOTAL.*?(\d+)', report_upper)
    if total_matches:
        for match in total_matches:
            if int(match) == gt_total:
                total_found = True
                break
    
    if total_found:
        score += 15
        feedback_parts.append("Total count correct (+15)")
    else:
        # Loose check: is the number just present?
        if str(gt_total) in report_upper:
            score += 5
            feedback_parts.append("Total count number present but label unclear (+5)")
        else:
            feedback_parts.append(f"Total count incorrect (expected {gt_total})")

    # 8. Verify Most Expensive (15 pts)
    if gt_most_exp:
        item_found = gt_most_exp["name"] in report_upper
        price_found = str(int(gt_most_exp["price"])) in report_upper # Check integer part of price
        
        if item_found and price_found:
            score += 15
            feedback_parts.append("Most expensive item correct (+15)")
        elif item_found:
            score += 10
            feedback_parts.append("Most expensive item name found, price unclear (+10)")
        elif price_found:
            score += 5
            feedback_parts.append("Max price found, item name unclear (+5)")

    # 9. Verify Least Expensive (15 pts)
    if gt_least_exp:
        item_found = gt_least_exp["name"] in report_upper
        price_found = str(int(gt_least_exp["price"])) in report_upper
        
        if item_found and price_found:
            score += 15
            feedback_parts.append("Least expensive item correct (+15)")
        elif item_found:
            score += 10
            feedback_parts.append("Least expensive item name found (+10)")
        elif price_found:
            score += 5
            feedback_parts.append("Min price found (+5)")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }