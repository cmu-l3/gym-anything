#!/usr/bin/env python3
"""Verifier for resolve_merge_conflicts task."""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_resolve_merge_conflicts(traj, env_info, task_info):
    """
    Verify that git merge conflicts were resolved correctly.

    Scoring Criteria:
    1. Git Clean State (10 pts): No uncommitted changes, merge finished.
    2. Merge Commit (10 pts): History shows a merge commit.
    3. No Conflict Markers (10 pts): Code is clean of <<<<<<<.
    4. Compilation (10 pts): 'mvn compile' succeeds.
    5. Content Verification (50 pts total):
       - Product.java (15 pts): Has category, discountPercent, and correct toString.
       - InventoryManager.java (15 pts): Has Streams logic AND discount method.
       - InventoryUtils.java (10 pts): Has formatCurrency AND calculateBulkDiscount.
       - pom.xml (10 pts): Has commons-lang3 AND commons-math3.
    6. VLM Verification (10 pts): Trajectory shows use of merge tools/process.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Read result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Git Clean State (10 pts)
    git_status = result.get("git_status_porcelain", "").strip()
    is_merge_in_progress = result.get("is_merge_in_progress", False)
    
    if not git_status and not is_merge_in_progress:
        score += 10
        feedback_parts.append("Git status clean")
    elif is_merge_in_progress:
        feedback_parts.append("Merge still in progress (incomplete)")
    else:
        feedback_parts.append("Uncommitted changes present")

    # 2. Merge Commit Exists (10 pts)
    # Check if top commit is a merge (usually starts with "Merge") or if graph shows merge
    git_log = result.get("git_log", "").lower()
    if "merge" in git_log:
        score += 10
        feedback_parts.append("Merge commit found")
    else:
        feedback_parts.append("No merge commit found in log")

    # 3. No Conflict Markers (10 pts)
    has_markers = result.get("has_conflict_markers", True)
    if not has_markers:
        score += 10
        feedback_parts.append("No conflict markers found")
    else:
        feedback_parts.append("Conflict markers (<<<<<<<) still present")
        # Critical fail condition for content points
        
    # 4. Compilation (10 pts)
    if result.get("compile_success", False):
        score += 10
        feedback_parts.append("Compilation successful")
    else:
        feedback_parts.append("Compilation failed")

    # 5. Content Verification
    # Only award content points if no conflict markers
    if not has_markers:
        # Product.java (15 pts)
        prod = result.get("product_content", "")
        prod_checks = [
            ("category", "category field/getter"),
            ("discountPercent", "discountPercent field/getter"),
            ("toString", "toString method")
        ]
        # Check if toString combines both (rough check: should be long)
        prod_pts = 0
        if "category" in prod and "getCategory" in prod: prod_pts += 5
        if "discountPercent" in prod and "getDiscountPercent" in prod: prod_pts += 5
        if "category" in prod and "discountPercent" in prod and "toString" in prod:
            # Check toString has both
            if 'category=' in prod and 'discount=' in prod:
                prod_pts += 5
        
        score += prod_pts
        feedback_parts.append(f"Product.java: {prod_pts}/15")

        # InventoryManager.java (15 pts)
        mgr = result.get("manager_content", "")
        mgr_pts = 0
        if "stream()" in mgr and "mapToDouble" in mgr: mgr_pts += 8 # Main's change
        if "calculateDiscountedTotal" in mgr: mgr_pts += 7 # Feature's change
        score += mgr_pts
        feedback_parts.append(f"InventoryManager.java: {mgr_pts}/15")

        # InventoryUtils.java (10 pts)
        utils = result.get("utils_content", "")
        utils_pts = 0
        if "formatCurrency" in utils: utils_pts += 5
        if "calculateBulkDiscount" in utils: utils_pts += 5
        score += utils_pts
        feedback_parts.append(f"InventoryUtils.java: {utils_pts}/10")

        # pom.xml (10 pts)
        pom = result.get("pom_content", "")
        pom_pts = 0
        if "commons-lang3" in pom: pom_pts += 5
        if "commons-math3" in pom: pom_pts += 5
        score += pom_pts
        feedback_parts.append(f"pom.xml: {pom_pts}/10")
    else:
        feedback_parts.append("Skipping content checks due to conflict markers")

    # 6. VLM Verification (10 pts)
    # This runs regardless of markers to give credit for trying
    vlm_score = 0
    from gym_anything.vlm import vlm_verify_intellij_task
    
    checklist = [
        "Are there any visible merge conflict dialogs or 3-way diff windows?",
        "Did the agent use a 'Merge' or 'Commit' action?",
        "Is the final screen free of red conflict indicators in the Project view?"
    ]
    
    vlm_result = vlm_verify_intellij_task(traj, env_info, 
                                        "Resolve git merge conflicts in IntelliJ IDEA", 
                                        checklist)
    
    if vlm_result:
        vlm_raw = vlm_result.get("vlm_score", 0)
        # Normalize 0-100 to 0-10
        vlm_score = min(10, int(vlm_raw / 10))
        score += vlm_score
        feedback_parts.append(f"VLM: {vlm_score}/10")
    else:
        # Fallback if VLM unavailable
        feedback_parts.append("VLM unavailable")

    passed = score >= 60 and result.get("compile_success", False) and not has_markers

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }