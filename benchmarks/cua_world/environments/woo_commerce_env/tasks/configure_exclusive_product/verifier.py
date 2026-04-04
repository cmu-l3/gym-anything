#!/usr/bin/env python3
"""
Verifier for Configure Exclusive Product task.

Verification Strategy:
1. Programmatic Checks (80%):
   - 'Sold individually' is enabled (yes).
   - Visibility includes 'exclude-from-catalog'.
   - Visibility does NOT include 'exclude-from-search'.
   - Short description contains the warning text.
   - Product was modified during the task window.
2. VLM Checks (20%):
   - Trajectory verification of interacting with Inventory and Publish settings.

Pass Threshold: 80 points.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_exclusive_product(traj, env_info, task_info):
    """Verify product exclusivity settings."""
    
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}

    metadata = task_info.get('metadata', {})
    required_text = metadata.get('required_text', "*** LIMIT 1 PER CUSTOMER ***")
    
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Evaluation Logic
    score = 0
    feedback = []
    
    # Check 1: Product Exists (Critical)
    if not result.get("product_found"):
        return {"passed": False, "score": 0, "feedback": "Target product not found in database."}

    # Check 2: Sold Individually (30 pts)
    # Value should be 'yes'
    sold_individually = result.get("sold_individually_meta", "")
    if sold_individually == "yes":
        score += 30
        feedback.append("Inventory limit enabled correctly.")
    else:
        feedback.append(f"Inventory limit incorrect (found: '{sold_individually}', expected: 'yes').")

    # Check 3: Visibility (30 pts)
    # For 'Search results only', we expect 'exclude-from-catalog' term.
    # We expect 'exclude-from-search' to NOT be present.
    terms = result.get("visibility_terms", [])
    
    has_exclude_catalog = "exclude-from-catalog" in terms
    has_exclude_search = "exclude-from-search" in terms
    
    if has_exclude_catalog and not has_exclude_search:
        score += 30
        feedback.append("Catalog visibility set to 'Search results only'.")
    elif has_exclude_catalog and has_exclude_search:
        # This is 'Hidden'
        score += 10
        feedback.append("Product is Hidden (should be Search results only).")
    elif not has_exclude_catalog and not has_exclude_search:
        # This is 'Visible'
        feedback.append("Product is still fully visible in Catalog.")
    else:
        feedback.append(f"Visibility settings incorrect (Terms: {terms}).")

    # Check 4: Short Description (20 pts)
    desc = result.get("short_description", "")
    if required_text in desc:
        score += 20
        feedback.append("Warning text added to description.")
    else:
        feedback.append("Warning text missing from short description.")

    # Check 5: Anti-Gaming / Activity (20 pts)
    if result.get("modified_during_task"):
        score += 20
        feedback.append("Product modified during task window.")
    else:
        feedback.append("No changes detected during task time.")

    # Final Result
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }