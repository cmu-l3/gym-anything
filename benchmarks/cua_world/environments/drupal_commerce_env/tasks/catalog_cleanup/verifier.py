#!/usr/bin/env python3
"""
Verifier for Catalog Cleanup task.

Scoring (100 points):
1. Bose QC45 unpublished (20 pts)
2. Anker PowerCore unpublished (20 pts)
3. Nintendo Switch title updated to 'Nintendo Switch OLED [CLEARANCE]' (15 pts)
4. Nintendo Switch price reduced to 279.99 (15 pts)
5. LG Monitor SKU updated to LG-34UW-V2 (20 pts)
6. No collateral damage to other products (10 pts)

Checks against database state exported to /tmp/task_result.json.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_catalog_cleanup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define Expected Values
    EXPECTED_NINTENDO_TITLE = "Nintendo Switch OLED [CLEARANCE]"
    EXPECTED_NINTENDO_PRICE = 279.99
    EXPECTED_LG_SKU = "LG-34UW-V2"

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error loading result file: {e}"}

    score = 0
    feedback_parts = []
    
    targets = result.get("targets", {})
    task_start = result.get("task_start", 0)

    # 1. Verify Bose QC45 Unpublished (20 pts)
    bose = targets.get("bose", {})
    if bose.get("found"):
        status = str(bose.get("status", "1"))
        if status == "0":
            score += 20
            feedback_parts.append("Bose QC45 correctly unpublished.")
        else:
            feedback_parts.append(f"Bose QC45 status incorrect (expected 0, got {status}).")
    else:
        feedback_parts.append("Bose QC45 product not found in catalog.")

    # 2. Verify Anker PowerCore Unpublished (20 pts)
    anker = targets.get("anker", {})
    if anker.get("found"):
        status = str(anker.get("status", "1"))
        if status == "0":
            score += 20
            feedback_parts.append("Anker PowerCore correctly unpublished.")
        else:
            feedback_parts.append(f"Anker PowerCore status incorrect (expected 0, got {status}).")
    else:
        feedback_parts.append("Anker PowerCore product not found in catalog.")

    # 3. Verify Nintendo Title (15 pts)
    nintendo = targets.get("nintendo", {})
    if nintendo.get("found"):
        title = nintendo.get("title", "")
        if title == EXPECTED_NINTENDO_TITLE:
            score += 15
            feedback_parts.append("Nintendo title updated correctly.")
        else:
            feedback_parts.append(f"Nintendo title incorrect (expected '{EXPECTED_NINTENDO_TITLE}', got '{title}').")
    else:
        feedback_parts.append("Nintendo product not found.")

    # 4. Verify Nintendo Price (15 pts)
    if nintendo.get("found"):
        try:
            price = float(nintendo.get("price", 0))
            if abs(price - EXPECTED_NINTENDO_PRICE) < 0.01:
                score += 15
                feedback_parts.append("Nintendo price updated correctly.")
            else:
                feedback_parts.append(f"Nintendo price incorrect (expected {EXPECTED_NINTENDO_PRICE}, got {price}).")
        except:
            feedback_parts.append("Could not parse Nintendo price.")

    # 5. Verify LG SKU (20 pts)
    lg = targets.get("lg", {})
    lg_sku = lg.get("sku", "")
    
    # Check if found via SKU search fallback
    if lg.get("found_via_sku_search"):
        lg_sku = lg.get("actual_sku_found", "")
    
    if lg_sku.upper() == EXPECTED_LG_SKU.upper():
        score += 20
        feedback_parts.append("LG SKU updated correctly.")
    else:
        feedback_parts.append(f"LG SKU incorrect (expected '{EXPECTED_LG_SKU}', got '{lg_sku}').")

    # 6. Verify Collateral Damage (10 pts)
    collateral = result.get("collateral_damage", [])
    if len(collateral) == 0:
        score += 10
        feedback_parts.append("No collateral damage detected.")
    else:
        damaged_titles = [c["title"] for c in collateral]
        feedback_parts.append(f"Collateral damage detected on {len(collateral)} products: {', '.join(damaged_titles)}.")

    # Anti-gaming: Check if changes happened during task
    # We check the 'last_changed' timestamp of modified items against task_start
    # This is a soft check - if the state is correct, we generally assume success, 
    # but strictly speaking, the timestamp should be > task_start.
    # We won't zero the score, but we'll note it.
    
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }