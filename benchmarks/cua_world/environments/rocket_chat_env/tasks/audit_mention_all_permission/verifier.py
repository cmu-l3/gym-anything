#!/usr/bin/env python3
import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are analyzing screenshots from an agent performing a security audit in Rocket.Chat.

The agent was asked to:
1. Navigate to the Administration > Permissions page.
2. Find the 'mention-all' permission.
3. Observe which roles are checked.

Look at the provided trajectory frames.
1. Did the agent open the Administration panel at some point?
2. Did the agent navigate to the Permissions section?
3. Did the agent view the 'mention-all' permission (or use the search bar to find permissions)?

Respond in JSON format:
{
    "opened_admin_panel": true/false,
    "viewed_permissions_page": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""

def verify_audit_mention_all(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Output file checks
    output_exists = result.get('output_exists', False)
    file_created = result.get('file_created_during_task', False)
    
    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Audit file ~/mention_all_audit.txt does not exist"}
    if not file_created:
        feedback_parts.append("Warning: Audit file may have been created before the task started.")
    
    score += 20
    feedback_parts.append("Audit file exists (+20)")

    # 2. Content Checks (Programmatic)
    output_content = result.get('output_content', '').lower()
    gt_roles = [r.lower() for r in result.get('ground_truth_roles', [])]
    gt_roles_set = set(gt_roles)
    
    # List of known Rocket.Chat roles to avoid penalizing standard English words (e.g., "The roles are...")
    known_roles = {"admin", "user", "bot", "guest", "anonymous", "app", "owner", "moderator", "leader"}
    
    # Check which known roles appear in the output text using word boundaries
    identified_roles = {r for r in known_roles if re.search(r'\b' + re.escape(r) + r'\b', output_content)}
    
    logger.info(f"Identified roles in output: {identified_roles}")
    logger.info(f"Ground truth roles: {gt_roles_set}")

    missing_roles = gt_roles_set - identified_roles
    extra_roles = identified_roles - gt_roles_set
    
    content_score = 0
    if not gt_roles_set:
        feedback_parts.append("Error: Ground truth roles empty. Setup might have failed.")
    else:
        if not missing_roles:
            score += 40
            content_score += 40
            feedback_parts.append("All correct roles identified (+40)")
        else:
            feedback_parts.append(f"Missing roles: {', '.join(missing_roles)}")
            
        if not extra_roles:
            score += 15
            content_score += 15
            feedback_parts.append("No false positive roles (+15)")
        else:
            feedback_parts.append(f"Extra/incorrect roles listed: {', '.join(extra_roles)}")

    # 3. VLM Trajectory Verification
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        vlm_result = query_vlm(images=frames, prompt=VLM_PROMPT)
        
        if vlm_result and vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            if parsed.get("viewed_permissions_page"):
                vlm_score += 25
                feedback_parts.append("VLM verified permissions page was viewed (+25)")
            elif parsed.get("opened_admin_panel"):
                vlm_score += 10
                feedback_parts.append("VLM verified admin panel was opened, but not permissions page (+10)")
            else:
                feedback_parts.append("VLM could not verify navigation to admin/permissions page")
        else:
            feedback_parts.append("VLM query failed or unavailable")
            # If programmatic content is perfectly correct but VLM fails, award the fallback points
            if content_score == 55:
                vlm_score += 25
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        if content_score == 55:
            vlm_score += 25

    score += vlm_score

    # Perfect file match and overall score is the success threshold
    passed = score >= 85 and output_exists and not missing_roles and not extra_roles
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }