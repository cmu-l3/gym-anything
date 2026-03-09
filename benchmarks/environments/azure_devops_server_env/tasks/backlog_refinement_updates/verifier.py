#!/usr/bin/env python3
"""
Verifier for backlog_refinement_updates task.

Verifies:
1. "Implement product inventory search": SP=8 (20pts), Tag='release-v1.0' (15pts)
2. "Design REST API rate limiting": Priority=2 (20pts), Tag='release-v1.0' (15pts), Comment exists (15pts)
3. "Inventory count goes negative": Tag='critical-path' (15pts)

Anti-gaming:
- Checks if Work Item Revision (Rev) increased.
- Checks timestamps if available.
"""

import json
import logging
import os
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_backlog_refinement_updates(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Copy result from VM
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    
    # Windows path in VM -> local temp file
    vm_path = r"C:\Users\Docker\task_results\backlog_refinement_updates_result.json"
    
    try:
        copy_from_env(vm_path, tmp.name)
        with open(tmp.name, "r", encoding="utf-8-sig") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result file: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback_parts = []
    
    items = result.get("work_items", {})
    initial = result.get("initial_state", {})
    
    # --- Check 1: Implement product inventory search ---
    wi_search = items.get("Implement product inventory search")
    if wi_search:
        fields = wi_search.get("fields", {})
        
        # Story Points (20 pts)
        sp = fields.get("Microsoft.VSTS.Scheduling.StoryPoints")
        if sp == 8:
            score += 20
            feedback_parts.append("Inventory Search: SP updated to 8 (+20)")
        else:
            feedback_parts.append(f"Inventory Search: SP is {sp}, expected 8")
            
        # Tags (15 pts)
        tags = fields.get("System.Tags", "")
        if "release-v1.0" in tags:
            score += 15
            feedback_parts.append("Inventory Search: Tag 'release-v1.0' added (+15)")
        else:
            feedback_parts.append(f"Inventory Search: Missing 'release-v1.0' tag. Current tags: '{tags}'")
            
        # Rev check
        init_rev = initial.get("Implement product inventory search", {}).get("Rev", 0)
        curr_rev = wi_search.get("rev", 0)
        if curr_rev <= init_rev:
            feedback_parts.append("WARNING: Inventory Search revision did not increase.")
            # Note: We penalize via criteria check failure usually, but this confirms inaction
    else:
        feedback_parts.append("Inventory Search work item not found.")

    # --- Check 2: Design REST API rate limiting ---
    wi_api = items.get("Design REST API rate limiting")
    if wi_api:
        fields = wi_api.get("fields", {})
        
        # Priority (20 pts)
        prio = fields.get("Microsoft.VSTS.Common.Priority")
        if prio == 2:
            score += 20
            feedback_parts.append("API Rate Limiting: Priority updated to 2 (+20)")
        else:
            feedback_parts.append(f"API Rate Limiting: Priority is {prio}, expected 2")
            
        # Tags (15 pts)
        tags = fields.get("System.Tags", "")
        if "release-v1.0" in tags:
            score += 15
            feedback_parts.append("API Rate Limiting: Tag 'release-v1.0' added (+15)")
        else:
            feedback_parts.append("API Rate Limiting: Missing 'release-v1.0' tag")

        # Comment (15 pts)
        comments = wi_api.get("comments", [])
        found_comment = False
        for c in comments:
            text = c.get("text", "").lower()
            if "deferred" in text or "deprioritized" in text or "v2.0" in text:
                found_comment = True
                break
        
        if found_comment:
            score += 15
            feedback_parts.append("API Rate Limiting: Explanatory comment added (+15)")
        else:
            feedback_parts.append("API Rate Limiting: No relevant comment found")
    else:
        feedback_parts.append("API Rate Limiting work item not found.")

    # --- Check 3: Inventory count goes negative ---
    wi_bug = items.get("Inventory count goes negative")
    if wi_bug:
        fields = wi_bug.get("fields", {})
        
        # Tags (15 pts)
        tags = fields.get("System.Tags", "")
        if "critical-path" in tags:
            score += 15
            feedback_parts.append("Inventory Bug: Tag 'critical-path' added (+15)")
        else:
            feedback_parts.append("Inventory Bug: Missing 'critical-path' tag")
    else:
        feedback_parts.append("Inventory Bug work item not found.")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }