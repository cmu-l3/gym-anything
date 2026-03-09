#!/usr/bin/env python3
"""
Verifier for restaurant_menu_design task.

Scoring (100 points, pass at 70):
1. File Checks (20pts)
   - Exists & Valid Format: 10
   - Page Count = 3: 10
2. Cover Page (20pts)
   - Title "Golden Fork": 10
   - Logo (Shape present): 10
3. Appetizers (30pts)
   - Header: 5
   - Items (3 items * 5pts): 15
   - Prices (3 prices * 3.33pts): 10
4. Entrees (30pts)
   - Header: 5
   - Items (3 items * 5pts): 15
   - Prices (3 prices * 3.33pts): 10
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_restaurant_menu(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env function available"}

    # Load result
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_path = tmp.name
        tmp.close()
        copy_from_env('/tmp/task_result.json', tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback = []

    # 1. File Checks
    if result.get('file_found') and result.get('file_valid'):
        score += 10
        feedback.append("File created successfully (10/10)")
    else:
        feedback.append("File not found or invalid (0/10)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    pc = result.get('page_count', 0)
    if pc == 3:
        score += 10
        feedback.append("Correct page count (10/10)")
    else:
        feedback.append(f"Incorrect page count: {pc}/3 (0/10)")

    # 2. Cover Page
    content = result.get('content', {})
    if content.get('has_title'):
        score += 10
        feedback.append("Restaurant title found (10/10)")
    else:
        feedback.append("Title 'Golden Fork' missing (0/10)")

    if result.get('logo_shape_found'):
        score += 10
        feedback.append("Logo shape detected (10/10)")
    else:
        feedback.append("No shape detected for logo (0/10)")

    # 3. Appetizers
    apps = content.get('appetizers', {})
    if apps.get('header'):
        score += 5
        feedback.append("Appetizer header found (5/5)")
    
    app_items_count = sum(1 for x in apps.get('items', []) if x)
    score += app_items_count * 5
    if app_items_count < 3:
        feedback.append(f"Missing appetizer items ({app_items_count}/3 found)")

    app_prices_count = sum(1 for x in apps.get('prices', []) if x)
    score += int(app_prices_count * 3.33)
    if app_prices_count < 3:
        feedback.append(f"Missing appetizer prices ({app_prices_count}/3 found)")

    # 4. Entrees
    ents = content.get('entrees', {})
    if ents.get('header'):
        score += 5
        feedback.append("Entree header found (5/5)")

    ent_items_count = sum(1 for x in ents.get('items', []) if x)
    score += ent_items_count * 5
    if ent_items_count < 3:
        feedback.append(f"Missing entree items ({ent_items_count}/3 found)")

    ent_prices_count = sum(1 for x in ents.get('prices', []) if x)
    score += int(ent_prices_count * 3.33)
    if ent_prices_count < 3:
        feedback.append(f"Missing entree prices ({ent_prices_count}/3 found)")

    # Cap score at 100 just in case of rounding
    score = min(100, score)
    
    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }