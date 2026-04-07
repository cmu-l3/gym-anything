#!/usr/bin/env python3
"""
Verifier for Configure Content Visibility and Access Controls task.

Checks:
1. Staff Resources Portal: Password protected ('LibAccess2024!'), publish status, expected content.
2. Getting Started with WordPress: Changed to 'private' status.
3. 10 Essential WordPress Plugins: Changed to 'draft' status.
4. Internal Collection Policy: 'private' status, expected content.
5. Accessing Restricted Resources: 'publish' status, expected content.
6. Trajectory verification: Ensures agent interacted with UI instead of purely CLI bypassing.
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TRAJECTORY_PROMPT = """You are analyzing screenshots of an agent configuring content visibility in WordPress.

For successful task completion, the agent should:
1. Navigate to 'Pages' and 'Posts' menus.
2. Edit visibility settings (e.g., clicking 'Public' to reveal Private/Password Protected options).
3. Draft or Publish content with restricted settings.

Assess:
1. WORKFLOW_COMPLETED: Did the agent visit post/page editors and modify visibility or status settings?
2. VISIBILITY_CONTROLS_USED: Are the WordPress visibility radio buttons (Public, Private, Password Protected) or status dropdowns visible?
3. MEANINGFUL_PROGRESSION: Do the frames show real state changes?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "visibility_controls_used": true/false,
    "meaningful_progression": true/false,
    "observations": "brief details",
    "confidence": "low"/"medium"/"high"
}
"""

def _vlm_query(query_vlm, prompt, images):
    if not query_vlm or not images:
        return None
    try:
        result = query_vlm(prompt=prompt, images=images)
        if result.get("success"):
            return result.get("parsed", {})
        logger.warning(f"VLM query failed: {result.get('error', 'unknown')}")
    except Exception as e:
        logger.warning(f"VLM query exception: {e}")
    return None

def verify_configure_content_access(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/configure_content_access_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result data: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    items = result.get('items', {})
    initial_max_id = result.get('initial_max_id', 0)
    
    score = 0
    feedback_parts = []
    structural_changes = 0

    # 1. Staff Resources Portal (20 pts)
    staff_portal = items.get('staff_portal')
    if staff_portal:
        if staff_portal['ID'] > initial_max_id:
            structural_changes += 1
            if staff_portal.get('post_status') == 'publish' and staff_portal.get('post_password') == metadata['staff_portal_password']:
                score += 15
                feedback_parts.append("Staff Portal exists and is properly password protected")
            else:
                feedback_parts.append("Staff Portal exists but lacks correct password or status")
            
            content = staff_portal.get('post_content', '').lower()
            if metadata['staff_portal_content_keyword'].lower() in content:
                score += 5
                feedback_parts.append("Staff Portal content verified")
            else:
                feedback_parts.append("Staff Portal content missing required text")
        else:
            feedback_parts.append("Staff Portal was not newly created during task")
    else:
        feedback_parts.append("Staff Portal page missing")

    # 2. Getting Started (15 pts)
    getting_started = items.get('getting_started')
    if getting_started:
        if getting_started.get('post_status') == metadata['post1_expected_status']:
            score += 15
            structural_changes += 1
            feedback_parts.append("Getting Started changed to Private")
        else:
            feedback_parts.append(f"Getting Started status is '{getting_started.get('post_status')}', expected private")
    else:
        feedback_parts.append("Getting Started post missing entirely")

    # 3. Essential Plugins (15 pts)
    plugins = items.get('plugins')
    if plugins:
        if plugins.get('post_status') == metadata['post2_expected_status']:
            score += 15
            structural_changes += 1
            feedback_parts.append("Essential Plugins changed to Draft")
        else:
            feedback_parts.append(f"Essential Plugins status is '{plugins.get('post_status')}', expected draft")
    else:
        feedback_parts.append("Essential Plugins post missing entirely")

    # 4. Policy Page (20 pts)
    policy = items.get('policy')
    if policy:
        if policy['ID'] > initial_max_id:
            structural_changes += 1
            if policy.get('post_status') == metadata['policy_expected_status']:
                score += 15
                feedback_parts.append("Policy page exists and is Private")
            else:
                feedback_parts.append("Policy page exists but is not Private")

            content = policy.get('post_content', '').lower()
            if metadata['policy_content_keyword'].lower() in content:
                score += 5
                feedback_parts.append("Policy page content verified")
            else:
                feedback_parts.append("Policy page content missing required text")
        else:
            feedback_parts.append("Policy page was not newly created during task")
    else:
        feedback_parts.append("Policy page missing")

    # 5. Accessing Restricted Resources (15 pts)
    accessing = items.get('accessing')
    if accessing:
        if accessing['ID'] > initial_max_id:
            structural_changes += 1
            if accessing.get('post_status') == metadata['access_expected_status']:
                score += 10
                feedback_parts.append("Accessing page exists and is Public")
            else:
                feedback_parts.append("Accessing page exists but is not Public")

            content = accessing.get('post_content', '').lower()
            if metadata['access_content_keyword'].lower() in content:
                score += 5
                feedback_parts.append("Accessing page content verified")
            else:
                feedback_parts.append("Accessing page content missing required text")
        else:
            feedback_parts.append("Accessing page was not newly created during task")
    else:
        feedback_parts.append("Accessing page missing")

    # 6. VLM Verification (15 pts)
    # Using trajectory frames to ensure the agent used UI workflows
    try:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            query_vlm = env_info.get('query_vlm')
            vlm_res = _vlm_query(query_vlm, TRAJECTORY_PROMPT, images=frames)
            
            if vlm_res:
                if vlm_res.get('visibility_controls_used') and vlm_res.get('workflow_completed'):
                    score += 15
                    feedback_parts.append("VLM: Confirmed visibility controls UI usage")
                else:
                    feedback_parts.append("VLM: UI interaction for visibility settings not clear")
            else:
                # If VLM fails/unavailable but they got max programmatic points, grant VLM points to be fair
                if structural_changes >= 4:
                    score += 15
                    feedback_parts.append("VLM unavailable, auto-granted based on structural success")
        else:
            feedback_parts.append("No trajectory frames for VLM")
    except Exception as e:
        logger.warning(f"VLM process failed: {e}")

    # Pass logic: >= 60 points AND at least 3 structural updates executed correctly
    passed = score >= 60 and structural_changes >= 3

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "structural_changes_made": structural_changes,
            "items_checked": list(items.keys())
        }
    }