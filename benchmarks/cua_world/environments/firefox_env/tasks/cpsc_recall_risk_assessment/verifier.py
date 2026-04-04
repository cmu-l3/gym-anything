#!/usr/bin/env python3
"""
Verifier for CPSC Product Recall Risk Assessment task.

Verifies:
1. Browser History: Visits to cpsc.gov and saferproducts.gov
2. Bookmarks: "Product Safety Research" folder with >= 6 bookmarks
3. Output File: Valid JSON, correct structure, formatted recall numbers
4. Content: At least 2 recalls per category (space heaters, power banks, sleepwear)

Pass Threshold: 60/100
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Task constants
REQUIRED_CATEGORIES = ["space_heaters", "power_banks", "childrens_sleepwear"]
RECALL_REGEX = r"^\d{2}-\d{3,}$"  # e.g., 24-071
MIN_RECALLS_PER_CAT = 2
MIN_BOOKMARKS = 6

def verify_cpsc_risk_assessment(traj, env_info, task_info):
    """
    Main verification function.
    """
    # 1. Setup access to environment files
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # 2. Retrieve the export summary (browser state)
    summary_data = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            copy_from_env("/tmp/task_result.json", tmp.name)
            tmp.close()
            with open(tmp.name, 'r') as f:
                summary_data = json.load(f)
            os.unlink(tmp.name)
    except Exception as e:
        logger.warning(f"Failed to read task result summary: {e}")

    # 3. Retrieve the user's output JSON file
    user_json_data = {}
    user_file_valid = False
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            # We try to copy even if summary says it doesn't exist, just in case
            copy_from_env("/home/ga/Documents/cpsc_risk_assessment.json", tmp.name)
            tmp.close()
            if os.path.getsize(tmp.name) > 0:
                with open(tmp.name, 'r') as f:
                    user_json_data = json.load(f)
                user_file_valid = True
            os.unlink(tmp.name)
    except Exception as e:
        logger.warning(f"Failed to retrieve/parse user output file: {e}")

    # =========================================================
    # SCORING LOGIC
    # =========================================================
    score = 0
    feedback = []
    
    # Criterion 1: Browser History (15 pts)
    cpsc_visits = summary_data.get("cpsc_visits", 0)
    safer_visits = summary_data.get("saferproducts_visits", 0)
    
    if cpsc_visits >= 3:
        score += 10
        feedback.append(f"CPSC.gov history verified ({cpsc_visits} pages) (+10)")
    elif cpsc_visits > 0:
        score += 5
        feedback.append(f"CPSC.gov history minimal ({cpsc_visits} pages) (+5)")
    else:
        feedback.append("No history of visiting cpsc.gov found")

    if safer_visits > 0:
        score += 5
        feedback.append(f"SaferProducts.gov history verified ({safer_visits} pages) (+5)")
    else:
        feedback.append("No history of visiting saferproducts.gov found")

    # Criterion 2: Bookmarks (15 pts)
    folder_exists = summary_data.get("bookmark_folder_exists", False)
    bm_count = summary_data.get("bookmark_folder_count", 0)
    
    if folder_exists:
        score += 5
        feedback.append("'Product Safety Research' bookmark folder found (+5)")
        
        if bm_count >= MIN_BOOKMARKS:
            score += 10
            feedback.append(f"Bookmark count met ({bm_count} >= {MIN_BOOKMARKS}) (+10)")
        elif bm_count >= 1:
            score += 5
            feedback.append(f"Bookmark count partial ({bm_count} < {MIN_BOOKMARKS}) (+5)")
        else:
            feedback.append("Bookmark folder is empty")
    else:
        feedback.append("'Product Safety Research' bookmark folder NOT found")

    # Criterion 3: File Existence & Freshness (10 pts)
    if user_file_valid:
        if summary_data.get("output_file_fresh", False):
            score += 10
            feedback.append("Output file exists, is valid JSON, and created during task (+10)")
        else:
            score += 5
            feedback.append("Output file exists but timestamp check failed (stale?) (+5)")
    else:
        feedback.append("Output file missing or invalid JSON")
        # Critical failure for remaining checks
        return {
            "passed": False, 
            "score": score, 
            "feedback": " | ".join(feedback)
        }

    # Criterion 4: JSON Structure (15 pts)
    cats_found = 0
    for cat in REQUIRED_CATEGORIES:
        if cat in user_json_data:
            cats_found += 1
    
    if cats_found == 3:
        score += 15
        feedback.append("All 3 required product categories present (+15)")
    else:
        pts = cats_found * 5
        score += pts
        feedback.append(f"Found {cats_found}/3 product categories (+{pts})")

    # Criterion 5: Data Content & Quality (45 pts)
    # 15 pts per category: 
    #   - 5 pts for >= 2 items
    #   - 5 pts for valid recall IDs
    #   - 5 pts for valid fields (product_name, hazard, manufacturer)
    
    for cat in REQUIRED_CATEGORIES:
        cat_data = user_json_data.get(cat, {})
        recalls = cat_data.get("recalls_found", [])
        
        # Check quantity
        if len(recalls) >= MIN_RECALLS_PER_CAT:
            score += 5
        else:
            # Partial credit for 1 item
            if len(recalls) == 1:
                score += 2

        # Check IDs
        valid_ids = 0
        valid_fields = 0
        
        for r in recalls:
            # Check ID format
            rid = str(r.get("recall_number", ""))
            if re.match(RECALL_REGEX, rid):
                valid_ids += 1
            
            # Check fields
            if r.get("product_name") and r.get("hazard") and r.get("manufacturer"):
                valid_fields += 1
        
        # Award ID points (scaled)
        if len(recalls) > 0:
            if valid_ids == len(recalls):
                score += 5
            elif valid_ids > 0:
                score += 3
                
            if valid_fields == len(recalls):
                score += 5
            elif valid_fields > 0:
                score += 3

    # Append summary feedback
    feedback.append(f"Content analysis complete. Found {sum(len(user_json_data.get(c,{}).get('recalls_found',[])) for c in REQUIRED_CATEGORIES)} total recalls.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }