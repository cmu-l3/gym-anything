#!/usr/bin/env python3
"""
Verifier for HTS Tariff Classification Task.
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_hts_tariff_classification(traj, env_info, task_info):
    """
    Verifies the HTS Tariff Classification task.
    
    Scoring Criteria (100 pts total):
    1. Browser History (15 pts): Visited hts.usitc.gov.
    2. Bookmarks (10 pts): "Trade Compliance" folder created with >= 3 bookmarks.
    3. JSON File Existence & Freshness (15 pts): File exists and modified during task.
    4. Data Correctness (60 pts):
       - 5 products * 12 pts each:
         - HTS Chapter correct (5 pts)
         - HTS Prefix (4-6 digits) match (5 pts)
         - Duty rate present (2 pts)
         
    Pass Threshold: 60 points.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verification failed: copy_from_env unavailable."}

    # Load Metadata Result (Browser state)
    metadata_result = {}
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp_meta:
        try:
            copy_from_env("/tmp/task_result.json", tmp_meta.name)
            with open(tmp_meta.name, 'r') as f:
                metadata_result = json.load(f)
        except Exception as e:
            logger.error(f"Failed to load metadata result: {e}")
        finally:
            try:
                os.unlink(tmp_meta.name)
            except: pass

    # Load User Output JSON
    user_data = {}
    output_valid = False
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp_output:
        try:
            # We assume export_result.sh leaves the file at original location,
            # but copy_from_env allows us to grab it.
            copy_from_env("/home/ga/Documents/tariff_classification.json", tmp_output.name)
            with open(tmp_output.name, 'r') as f:
                user_data = json.load(f)
            output_valid = True
        except Exception as e:
            logger.error(f"Failed to load user output file: {e}")
        finally:
            try:
                os.unlink(tmp_output.name)
            except: pass

    # --- SCORING ---
    score = 0
    feedback = []

    # 1. Browser History (15 pts)
    hts_visits = metadata_result.get("hts_visits", 0)
    if hts_visits > 0:
        score += 15
        feedback.append("Browser history confirmed (hts.usitc.gov visited).")
    else:
        feedback.append("No history of visiting USITC HTS database found (-15 pts).")

    # 2. Bookmarks (10 pts)
    bm_folder = metadata_result.get("bookmark_folder_exists", False)
    bm_count = metadata_result.get("bookmark_count", 0)
    if bm_folder:
        if bm_count >= 3:
            score += 10
            feedback.append(f"Bookmark folder 'Trade Compliance' found with {bm_count} bookmarks.")
        else:
            score += 5
            feedback.append(f"Bookmark folder found, but only {bm_count}/3 bookmarks (-5 pts).")
    else:
        feedback.append("Bookmark folder 'Trade Compliance' not found (-10 pts).")

    # 3. File Existence & Freshness (15 pts)
    file_exists = metadata_result.get("file_exists", False)
    file_fresh = metadata_result.get("file_fresh", False)
    
    if file_exists and output_valid:
        if file_fresh:
            score += 15
            feedback.append("Report file exists and was created during task.")
        else:
            score += 5
            feedback.append("Report file exists but timestamp suggests it wasn't created during this run (-10 pts).")
    else:
        feedback.append("Report file not found or invalid JSON (-15 pts).")
        # Critical failure for data check
        return {"passed": False, "score": score, "feedback": "\n".join(feedback)}

    # 4. Data Correctness (60 pts)
    # Products map to check against
    # 1. Battery: 8507.6x (Chapter 85)
    # 2. Tea: 0902.1x (Chapter 09)
    # 3. Bolts: 7318.1x (Chapter 73)
    # 4. Mugs: 6911.x or 6912.x (Chapter 69)
    # 5. T-shirt: 6109.x (Chapter 61)
    
    products_found = user_data.get("products", [])
    if not isinstance(products_found, list):
        feedback.append("JSON structure incorrect: 'products' is not a list.")
        return {"passed": False, "score": score, "feedback": "\n".join(feedback)}

    # Helper to clean codes
    def clean_code(c):
        return re.sub(r'[^0-9]', '', str(c))

    # We need to map user entries to expected items. 
    # Heuristic: Check HTS chapter matches first, then keyword matches in description.
    
    expected_items = [
        {"key": "battery", "chapters": [85], "prefix": "85076", "keywords": ["battery", "lithium"]},
        {"key": "tea", "chapters": [9, "09"], "prefix": "09021", "keywords": ["tea", "green"]},
        {"key": "bolts", "chapters": [73], "prefix": "73181", "keywords": ["bolt", "screw", "hex"]},
        {"key": "mugs", "chapters": [69], "prefix": ["6911", "6912"], "keywords": ["mug", "cup", "ceramic", "stoneware"]},
        {"key": "tshirt", "chapters": [61], "prefix": "6109", "keywords": ["shirt", "tee", "knit"]}
    ]

    item_scores = 0
    
    for expected in expected_items:
        best_match = None
        
        # Try to find matching entry
        for entry in products_found:
            desc = str(entry.get("description", "")).lower()
            chap = entry.get("hts_chapter", 0)
            code = clean_code(entry.get("hts_code", ""))
            
            # Match by keywords
            if any(k in desc for k in expected["keywords"]):
                best_match = entry
                break
            # Or match by chapter if description vague
            if str(chap).zfill(2) == str(expected["chapters"][0]).zfill(2):
                best_match = entry
                break
                
        if best_match:
            # Score this item
            item_score = 0
            
            # 1. Chapter (5 pts)
            chap = str(best_match.get("hts_chapter", "0")).zfill(2)
            valid_chapters = [str(x).zfill(2) for x in expected["chapters"]]
            if chap in valid_chapters:
                item_score += 5
            
            # 2. Prefix (5 pts)
            code = clean_code(best_match.get("hts_code", ""))
            valid_prefixes = expected["prefix"]
            if isinstance(valid_prefixes, str): valid_prefixes = [valid_prefixes]
            
            if any(code.startswith(p) for p in valid_prefixes):
                item_score += 5
            
            # 3. Duty Rate (2 pts) - lenient check for presence
            rate = str(best_match.get("general_duty_rate", "")).lower()
            if "%" in rate or "free" in rate or "no" in rate or re.search(r'\d', rate):
                item_score += 2
            
            item_scores += item_score
            feedback.append(f"Item '{expected['key']}': {item_score}/12 pts.")
        else:
            feedback.append(f"Item '{expected['key']}' not found in report (-12 pts).")

    score += item_scores

    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }