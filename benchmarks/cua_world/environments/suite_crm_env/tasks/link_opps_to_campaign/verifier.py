#!/usr/bin/env python3
"""
Verifier for link_opps_to_campaign task.

Verifies:
1. Campaign 'Spring Tech Conference' Actual Cost was updated to 4500.
2. The 3 Opportunities were linked to the correct Campaign ID.
3. Modifications occurred AFTER the task started (anti-gaming).
4. VLM trajectory verification ensures the UI was actually used.
"""

import json
import os
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating an AI agent's performance on a CRM workflow task.

The agent was asked to:
1. Navigate to the Campaigns module and update the actual cost of a campaign.
2. Navigate to the Opportunities module and link three specific opportunities to that campaign.

Look closely at these screenshots taken during the agent's trajectory. Do you see evidence that the agent navigated through the SuiteCRM user interface (e.g., viewing lists, editing forms, selecting lookups) to perform these tasks?

Respond with a JSON object containing:
{
  "interacted_with_campaigns": boolean,
  "interacted_with_opportunities": boolean,
  "confidence": "high" | "medium" | "low",
  "reasoning": "string"
}
"""

def verify_link_opps(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_cost = metadata.get('expected_cost', 4500.0)
    
    # 1. Retrieve the results JSON from the environment
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    task_start = result.get('task_start', 0)
    campaign = result.get('campaign', {})
    opps = result.get('opportunities', {})

    camp_id = campaign.get('id', '')
    camp_cost = float(campaign.get('actual_cost', 0.0))
    camp_mtime = campaign.get('mtime', 0)

    score = 0
    feedback_parts = []
    
    # Check 1: Campaign Cost Updated
    campaign_updated = False
    if camp_id and abs(camp_cost - expected_cost) < 0.01:
        if camp_mtime >= task_start:
            campaign_updated = True
            score += 25
            feedback_parts.append("Campaign cost updated successfully.")
        else:
            feedback_parts.append("Campaign cost is correct, but was modified BEFORE task started (anti-gaming trigger).")
    else:
        feedback_parts.append(f"Campaign cost incorrect: expected {expected_cost}, got {camp_cost}.")

    # Check 2: Opportunities Linked
    linked_count = 0
    opp_names = ["Alpha Tech Upgrade", "Beta Corp License", "Gamma LLC Support"]
    
    for opp_name in opp_names:
        opp_data = opps.get(opp_name, {})
        opp_camp_id = opp_data.get('campaign_id', '')
        opp_mtime = opp_data.get('mtime', 0)
        
        if camp_id and opp_camp_id == camp_id:
            if opp_mtime >= task_start:
                linked_count += 1
                score += 15
                feedback_parts.append(f"'{opp_name}' successfully linked.")
            else:
                feedback_parts.append(f"'{opp_name}' linked, but modified BEFORE task started.")
        else:
            feedback_parts.append(f"'{opp_name}' NOT correctly linked.")

    # Check 3: VLM Trajectory Verification
    vlm_success = False
    try:
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        if images:
            vlm_response = query_vlm(images=images, prompt=VLM_PROMPT)
            parsed = vlm_response.get('parsed', {})
            
            if parsed.get('interacted_with_campaigns') or parsed.get('interacted_with_opportunities'):
                vlm_success = True
                score += 30
                feedback_parts.append(f"VLM verified UI interaction (Reason: {parsed.get('reasoning')}).")
            else:
                feedback_parts.append("VLM did not detect sufficient UI interaction in trajectory.")
        else:
            feedback_parts.append("No trajectory images available for VLM verification.")
    except Exception as e:
        logger.error(f"VLM verification failed: {e}")
        feedback_parts.append("VLM verification failed due to error.")

    # Final scoring
    # Requirements to pass: Update the campaign AND link at least two opps AND perform via UI
    passed = campaign_updated and (linked_count >= 2) and vlm_success

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "campaign_updated": campaign_updated,
            "opportunities_linked": linked_count,
            "vlm_verified": vlm_success
        }
    }