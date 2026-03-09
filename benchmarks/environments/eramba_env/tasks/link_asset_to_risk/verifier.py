#!/usr/bin/env python3
"""
Verifier for link_asset_to_risk task.

Checks:
1. Database: Asset linked to Risk (assets_risks table)
2. Database: Risk description updated with specific text
3. Anti-gaming: Timestamp check
4. VLM: Visual confirmation of the link in the UI
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_link_asset_to_risk(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Result JSON
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
    
    # 2. Check Database Results
    link_exists = result.get("link_exists", False)
    text_updated = result.get("text_updated", False)
    modified_recently = result.get("risk_modified_recently", False)

    if link_exists:
        score += 40
        feedback_parts.append("Asset successfully linked to Risk.")
    else:
        feedback_parts.append("Asset NOT linked to Risk.")

    if text_updated:
        score += 30
        feedback_parts.append("Risk description updated with required text.")
    else:
        feedback_parts.append("Risk description NOT updated correctly.")

    if modified_recently:
        score += 10
        feedback_parts.append("Risk record modification detected during task.")
    else:
        feedback_parts.append("Risk record not modified during task time window.")

    # 3. VLM Verification
    # We check if the final screen or trajectory shows the assets tab or the linked asset
    vlm_score = 0
    final_screenshot = get_final_screenshot(traj)
    
    if final_screenshot and os.path.exists(final_screenshot):
        prompt = """
        Review this screenshot from the Eramba GRC Risk Management module.
        
        Look for:
        1. A Risk detail view or edit screen (likely 'Unencrypted Data at Rest').
        2. An 'Assets' or 'Business Assets' section/tab.
        3. The presence of 'Patient Records Database' listed as a linked item.
        
        Answer in JSON:
        {
            "risk_view_visible": true/false,
            "asset_linked_visible": true/false
        }
        """
        
        try:
            vlm_resp = query_vlm(prompt=prompt, image=final_screenshot)
            if vlm_resp.get("success"):
                parsed = vlm_resp.get("parsed", {})
                if parsed.get("asset_linked_visible"):
                    vlm_score = 20
                    feedback_parts.append("Visual verification confirmed Asset link.")
                elif parsed.get("risk_view_visible"):
                    vlm_score = 10
                    feedback_parts.append("Visual verification sees Risk view but not clear link.")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
    
    score += vlm_score

    # Pass Criteria
    # Must have database link (40) AND text update (30) AND timestamp (10) = 80 min for hard pass logic
    # But strict pass threshold usually 80+
    
    passed = (link_exists and text_updated and modified_recently)
    
    # Allow passing if database checks pass, even if VLM is ambiguous
    if score >= 80:
        passed = True

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }