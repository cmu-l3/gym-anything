#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_backlog_hierarchy(traj, env_info, task_info):
    """
    Verify that User Stories have been reparented to the correct Features.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define Expected Hierarchy (Ground Truth)
    # The keys match the Feature titles, values match expected User Story titles
    expected_structure = {
        "Shopping Cart & Checkout": {
            "Implement shopping cart persistence",
            "Apply discount codes at checkout",
            "One-click purchase for saved payment methods",
            "Guest checkout without account creation"
        },
        "Search & Discovery": {
            "Product recommendation engine",
            "Implement full-text product search",
            "Add search filters by category and price",
            "Search autocomplete suggestions"
        },
        "User Account Management": {
            "Two-factor authentication setup",
            "Password reset via email",
            "User profile editing page"
        }
    }

    # Fetch result from environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: Export script saves to C:\Users\Docker\task_results\...
        # We need to use the correct path convention for the copy_from_env tool
        copy_from_env("C:/Users/Docker/task_results/fix_backlog_hierarchy_result.json", temp_file.name)
        
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or parse task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    actual_hierarchy = result_data.get("hierarchy", {})
    
    score = 0
    feedback = []
    
    # Grading Logic
    # We check each Feature group
    
    for feature, expected_stories in expected_structure.items():
        actual_stories = set(actual_hierarchy.get(feature, []))
        
        # Calculate intersection
        correct_in_group = expected_stories.intersection(actual_stories)
        missing_from_group = expected_stories - actual_stories
        extras_in_group = actual_stories - expected_stories
        
        # Points: 
        # Total 100 points roughly divided by 3 groups ~ 33 pts each
        # Let's say 30 pts per group, +10 bonus for clean state
        
        # Per-group scoring:
        # Full points if exact match. Partial deduction for errors.
        
        group_score = 0
        if len(expected_stories) > 0:
            match_ratio = len(correct_in_group) / len(expected_stories)
            group_score = 30 * match_ratio
            
            # Penalize for extras (wrong items moved here)
            if extras_in_group:
                group_score -= (5 * len(extras_in_group))
        
        group_score = max(0, group_score) # No negative scores per group
        score += group_score
        
        if len(missing_from_group) == 0 and len(extras_in_group) == 0:
            feedback.append(f"✅ Feature '{feature}': Perfect")
        else:
            feedback.append(f"⚠️ Feature '{feature}': Found {len(actual_stories)}/{len(expected_stories)} expected.")
            if missing_from_group:
                feedback.append(f"   Missing: {', '.join(missing_from_group)}")
            if extras_in_group:
                feedback.append(f"   Incorrectly added: {', '.join(extras_in_group)}")

    # Check for Orphans
    orphans = actual_hierarchy.get("ORPHAN", [])
    if orphans:
        score -= (5 * len(orphans)) # Penalty for leaving items orphaned
        feedback.append(f"❌ Orphans remaining: {', '.join(orphans)}")
    else:
        score += 10 # Bonus for 0 orphans
        feedback.append("✅ No orphaned items remaining.")

    # Normalize Score
    score = min(100, max(0, int(score)))
    
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }