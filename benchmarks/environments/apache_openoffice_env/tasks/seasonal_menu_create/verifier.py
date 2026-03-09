#!/usr/bin/env python3
"""
Verifier for seasonal_menu_create task.
Verifies ODT structure (Headings, Tables, TOC) and Content (Menu Items, Prices).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_seasonal_menu(traj, env_info, task_info):
    """
    Verify the created seasonal menu document.
    Criteria:
    1. File exists and is > 8KB (Gate).
    2. Structure: H1 count (categories), H2 count, Table count, TOC, Page Numbers.
    3. Content: Check for presence of restaurant name and specific menu items/prices.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Scoring constants
    SCORING = {
        "file_exists": 5,
        "toc": 15,
        "h1_structure": 20,
        "h2_structure": 5,
        "tables": 20,
        "page_numbers": 10,
        "content_items": 15,
        "content_prices": 10
    }
    
    score = 0
    feedback = []
    
    # 1. File Check (Gate)
    if not result.get("file_exists"):
        return {"passed": False, "score": 0, "feedback": "Output file not found."}
    
    file_size_kb = result.get("file_size", 0) / 1024
    if file_size_kb < 8:
        # Penalize but allow partial scoring if structure is perfect (unlikely for <8kb)
        feedback.append(f"File size too small ({file_size_kb:.1f}KB), expected >8KB.")
    else:
        score += SCORING["file_exists"]
        feedback.append("File exists and has sufficient size.")

    # 2. Structure Checks
    h1_count = result.get("heading1_count", 0)
    if h1_count >= 6:
        score += SCORING["h1_structure"]
        feedback.append(f"Correct Heading 1 structure ({h1_count} sections).")
    elif h1_count > 0:
        score += 10 # Partial
        feedback.append(f"Partial Heading 1 structure ({h1_count}/6 sections).")
    else:
        feedback.append("No Heading 1 styles found.")

    h2_count = result.get("heading2_count", 0)
    if h2_count >= 2:
        score += SCORING["h2_structure"]
        feedback.append("Correct Heading 2 structure.")
    elif h2_count > 0:
        score += 2
        feedback.append("Partial Heading 2 structure.")

    table_count = result.get("table_count", 0)
    if table_count >= 6:
        score += SCORING["tables"]
        feedback.append(f"Correct table usage ({table_count} tables).")
    elif table_count > 0:
        score += 10 # Partial
        feedback.append(f"Partial table usage ({table_count}/6 tables).")
    else:
        feedback.append("No tables found for menu items.")

    if result.get("has_toc"):
        score += SCORING["toc"]
        feedback.append("Table of Contents found.")
    else:
        feedback.append("Table of Contents missing.")

    if result.get("has_page_numbers"):
        score += SCORING["page_numbers"]
        feedback.append("Page numbers found.")
    else:
        feedback.append("Page numbers missing.")

    # 3. Content Checks
    text = result.get("text_content", "").lower()
    
    # Check Restaurant Name
    if "thornfield" in text:
        feedback.append("Restaurant name verified.")
    else:
        feedback.append("Restaurant name 'Thornfield' not found.")
        
    # Check Sample Items (from metadata/task definition)
    # Sample set: Ramp, Duck, Morel, Scallops, Strip, Lemon
    sample_items = ["ramp", "duck", "morel", "scallop", "strip", "lemon"]
    items_found = sum(1 for item in sample_items if item in text)
    
    if items_found >= 5:
        score += SCORING["content_items"]
        feedback.append(f"Menu content verified ({items_found}/6 sample items).")
    elif items_found >= 3:
        score += 7
        feedback.append(f"Partial menu content ({items_found}/6 sample items).")
    else:
        feedback.append("Menu content missing or incorrect.")

    # Check Prices (look for specific price points from JSON)
    # $16, $19, $28, $38, $46, $14
    sample_prices = ["16", "19", "28", "38", "46", "14"]
    prices_found = sum(1 for p in sample_prices if p in text)
    
    if prices_found >= 4:
        score += SCORING["content_prices"]
        feedback.append("Prices verified.")
    else:
        feedback.append("Prices missing or incorrect.")

    # 4. Anti-Gaming Check
    if not result.get("file_created_during_task", True):
         feedback.append("WARNING: File timestamp suggests it was not created during this session.")
         # We might penalize heavily here, but for now just warn in feedback or cap score
         score = min(score, 50)

    # Final Pass Determination
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }