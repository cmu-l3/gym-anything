#!/usr/bin/env python3
"""
Verifier for configure_branch_policies task.
Verifies that Azure DevOps branch policies are correctly configured for 'main'.
"""

import json
import logging
import os
import tempfile
import sys

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Policy Type IDs (Standard ADO UUIDs)
POLICY_TYPES = {
    "min_reviewers": "fa4e907d-c16b-4a4c-9dfa-4906e5d171dd",
    "work_item_linking": "40e92b44-2fe1-4dd6-b3d8-ce34c45c55b1",
    "comment_resolution": "c6a1889d-b943-4856-b76f-9e46bb6b0df2"
}

def verify_configure_branch_policies(traj, env_info, task_info):
    """
    Verifies the configuration of branch policies.
    
    Criteria:
    1. Min Reviewers Policy: Exists, Enabled, Count >= 2 (35 pts)
    2. Work Item Linking Policy: Exists, Enabled, Required (30 pts)
    3. Comment Resolution Policy: Exists, Enabled, Required (30 pts)
    4. Anti-gaming: Policies created after task start (5 pts)
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment interface (copy_from_env) not available."}

    # Define paths
    # Note: Windows path in VM, mapped to temp file in host
    win_result_path = r"C:\Users\Docker\task_results\configure_branch_policies_result.json"
    
    # Create temp file for the result
    fd, temp_path = tempfile.mkstemp(suffix=".json")
    os.close(fd)
    
    try:
        # Copy result file
        try:
            copy_from_env(win_result_path, temp_path)
        except Exception as e:
            logger.error(f"Failed to copy result file: {e}")
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "Could not retrieve task results. Did the export script run?"
            }

        # Parse JSON
        with open(temp_path, 'r', encoding='utf-8') as f:
            try:
                data = json.load(f)
            except json.JSONDecodeError:
                return {"passed": False, "score": 0, "feedback": "Result file contains invalid JSON."}

        # Extract data
        policies = data.get("policies", [])
        task_start = data.get("task_start_timestamp", 0)
        
        score = 0
        feedback = []
        
        # Helper to find policy
        def find_policy(type_id):
            matches = [p for p in policies if p.get("type_id") == type_id and p.get("scope_match_main") is True]
            # Return the "best" match (enabled and blocking prefers) if multiple exist
            # But usually there's only one per type per scope.
            return matches[0] if matches else None

        # 1. VERIFY MIN REVIEWERS
        p_reviewers = find_policy(POLICY_TYPES["min_reviewers"])
        if p_reviewers:
            if p_reviewers.get("is_enabled"):
                settings = p_reviewers.get("settings", {})
                count = settings.get("minimumApproverCount", 0)
                if count >= 2:
                    score += 35
                    feedback.append(f"Min Reviewers: Correct (Set to {count})")
                else:
                    score += 15
                    feedback.append(f"Min Reviewers: Count too low ({count} < 2)")
            else:
                feedback.append("Min Reviewers: Policy exists but is Disabled")
        else:
            feedback.append("Min Reviewers: Policy NOT found on 'main'")

        # 2. VERIFY WORK ITEM LINKING
        p_workitems = find_policy(POLICY_TYPES["work_item_linking"])
        if p_workitems:
            if p_workitems.get("is_enabled"):
                if p_workitems.get("is_blocking"):
                    score += 30
                    feedback.append("Work Item Linking: Correct (Required)")
                else:
                    score += 15
                    feedback.append("Work Item Linking: Set to Optional (Should be Required/Blocking)")
            else:
                feedback.append("Work Item Linking: Disabled")
        else:
            feedback.append("Work Item Linking: Policy NOT found on 'main'")

        # 3. VERIFY COMMENT RESOLUTION
        p_comments = find_policy(POLICY_TYPES["comment_resolution"])
        if p_comments:
            if p_comments.get("is_enabled"):
                if p_comments.get("is_blocking"):
                    score += 30
                    feedback.append("Comment Resolution: Correct (Required)")
                else:
                    score += 15
                    feedback.append("Comment Resolution: Set to Optional (Should be Required/Blocking)")
            else:
                feedback.append("Comment Resolution: Disabled")
        else:
            feedback.append("Comment Resolution: Policy NOT found on 'main'")

        # 4. ANTI-GAMING (Timestamp check)
        # Check if at least one valid policy was created AFTER task start
        valid_policies = [p_reviewers, p_workitems, p_comments]
        created_fresh = False
        for p in valid_policies:
            if p:
                p_time = p.get("created_timestamp", 0)
                # Allow a small buffer (e.g. clock drift), but generally p_time > task_start
                if p_time >= task_start - 5:
                    created_fresh = True
                    break
        
        if created_fresh:
            score += 5
        elif score > 0:
            feedback.append("(Warning: Policies appear to pre-date task start)")

        # Final check
        passed = score >= 90 # Strict pass threshold for config tasks
        
        return {
            "passed": passed,
            "score": score,
            "feedback": "; ".join(feedback)
        }

    finally:
        # Cleanup
        if os.path.exists(temp_path):
            os.remove(temp_path)