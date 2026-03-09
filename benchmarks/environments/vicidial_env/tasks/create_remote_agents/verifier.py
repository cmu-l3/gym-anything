#!/usr/bin/env python3
"""
Verifier for create_remote_agents task.

Checks:
1. Database contains entries for users 7201, 7202, 7203.
2. Field values match requirements (Lines, Extension, Campaign, etc.).
3. Anti-gaming: Verify net new entries were created.
4. VLM: Verify UI interaction via trajectory.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_remote_agents(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_agents = metadata.get('expected_agents', {})

    score = 0
    feedback_parts = []
    
    # 1. Check Database Entries (Maximum 80 points)
    # 20 pts for existence of all 3
    # 20 pts per agent for correct fields (total 60)
    
    agents_found = 0
    field_score = 0
    
    result_agents = result.get('agents', {})
    
    for user_id, expected in expected_agents.items():
        actual = result_agents.get(user_id, {})
        
        if actual.get('exists'):
            agents_found += 1
            
            # Check fields
            agent_field_points = 0
            agent_feedback = []
            
            # Lines (4 pts)
            if str(actual.get('lines')) == str(expected.get('lines')):
                agent_field_points += 4
            else:
                agent_feedback.append(f"Lines: {actual.get('lines')} != {expected.get('lines')}")

            # Conf Ext (4 pts)
            if str(actual.get('conf_ext')) == str(expected.get('conf_ext')):
                agent_field_points += 4
            else:
                agent_feedback.append(f"Conf: {actual.get('conf_ext')} != {expected.get('conf_ext')}")

            # Status (4 pts)
            if str(actual.get('status')) == str(expected.get('status')):
                agent_field_points += 4
            else:
                agent_feedback.append(f"Status: {actual.get('status')} != {expected.get('status')}")

            # Campaign (4 pts)
            if str(actual.get('campaign')) == str(expected.get('campaign')):
                agent_field_points += 4
            else:
                agent_feedback.append(f"Camp: {actual.get('campaign')} != {expected.get('campaign')}")

            # Ext Number (4 pts)
            if str(actual.get('external_extension')) == str(expected.get('ext_number')):
                agent_field_points += 4
            else:
                agent_feedback.append(f"Ext: {actual.get('external_extension')} != {expected.get('ext_number')}")
            
            field_score += agent_field_points
            
            if agent_feedback:
                feedback_parts.append(f"Agent {user_id} issues: " + ", ".join(agent_feedback))
            else:
                feedback_parts.append(f"Agent {user_id} perfect")
        else:
            feedback_parts.append(f"Agent {user_id} MISSING")

    # Score calculation
    # Existence score
    if agents_found == 3:
        score += 20
    elif agents_found > 0:
        score += (agents_found * 5)
    
    # Field score (max 60)
    score += field_score

    # 2. Anti-Gaming Check (10 points)
    initial_count = int(result.get('initial_total_count', 0))
    current_count = int(result.get('current_total_count', 0))
    net_new = current_count - initial_count
    
    if net_new >= 3:
        score += 10
        feedback_parts.append("Anti-gaming: New entries confirmed")
    elif net_new > 0:
        score += 5
        feedback_parts.append(f"Anti-gaming: Only {net_new} new entries found")
    else:
        feedback_parts.append("Anti-gaming WARNING: No net new entries")

    # 3. VLM Verification (10 points)
    # Check if we see the form being filled or the list
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = """
        Analyze these screenshots of the Vicidial Admin interface.
        Did the agent navigate to the "Remote Agents" section and interact with a form to add new agents?
        Look for:
        1. "ADD NEW REMOTE AGENT" header or form.
        2. Fields like "User Start", "Number of Lines", "External Extension".
        3. A list of remote agents showing entries.
        
        Reply with JSON: {"interaction_verified": true/false, "reason": "..."}
        """
        try:
            vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
            if vlm_res.get('success') and vlm_res.get('parsed', {}).get('interaction_verified'):
                score += 10
                feedback_parts.append("VLM: UI interaction verified")
            else:
                feedback_parts.append("VLM: UI interaction NOT clear")
        except Exception:
            feedback_parts.append("VLM: Verification failed")
    else:
        feedback_parts.append("VLM: No frames")

    # Final logic
    passed = score >= 60 and agents_found == 3
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }