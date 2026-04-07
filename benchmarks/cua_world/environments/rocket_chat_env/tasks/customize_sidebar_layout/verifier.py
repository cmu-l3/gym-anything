#!/usr/bin/env python3
"""
Verifier for Customize Sidebar Layout task.

MULTIPLE INDEPENDENT SIGNALS:
1. API verification of Account Preferences (Group, Sort, View Mode)
2. API verification of Channel Subscriptions (Favorite, Hidden)
3. VLM Trajectory check to ensure agent actually interacted with settings
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Import VLM utils (handling fallback if framework modules aren't available)
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    logger.warning("VLM framework not directly importable, VLM checks will be skipped.")

VLM_PROMPT = """You are analyzing a sequence of screenshots from an agent customizing Rocket.Chat.

The user was asked to:
1. Favorite a channel.
2. Hide a channel.
3. Modify their Sidebar Preferences (My Account > Preferences > Sidebar).

Look at the trajectory frames and assess:
1. WORKFLOW_ATTEMPTED: Did the agent navigate to the "Preferences" or "My Account" screen at any point?
2. SIDEBAR_INTERACTION: Did the agent interact with channel menus (e.g. clicking the three dots next to a channel) to hide or favorite?

Respond in JSON format:
{
    "workflow_attempted": true/false,
    "sidebar_interaction": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""

def verify_customize_sidebar_layout(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_sort = metadata.get('expected_sort', 'alphabetical')
    expected_group = metadata.get('expected_group', True)
    expected_view = metadata.get('expected_view', 'condensed')
    
    # 1. Fetch JSON results via copy_from_env
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
    
    preferences = result.get("preferences", {})
    rel_sub = result.get("release_updates_sub", {})
    gen_sub = result.get("general_sub", {})

    # Criterion 1: release-updates marked as favorite
    # API indicates 'f' boolean field
    if rel_sub.get("f", False) is True:
        score += 16
        feedback_parts.append("#release-updates is Favorited")
    else:
        feedback_parts.append("#release-updates is NOT Favorited")

    # Criterion 2: general is hidden
    # API indicates 'open' boolean field is False when hidden
    # It defaults to True. If it's False, the agent successfully hid it.
    if gen_sub.get("open", True) is False:
        score += 16
        feedback_parts.append("#general is Hidden")
    else:
        feedback_parts.append("#general is NOT Hidden")

    # Criterion 3: Sort by Alphabetical
    if preferences.get("sidebarSortby", "") == expected_sort:
        score += 16
        feedback_parts.append(f"Sort by set to {expected_sort}")
    else:
        feedback_parts.append("Sort by NOT set correctly")

    # Criterion 4: Group by Type
    if preferences.get("sidebarGroupByType", False) == expected_group:
        score += 16
        feedback_parts.append("Group by Type is Enabled")
    else:
        feedback_parts.append("Group by Type is NOT Enabled")

    # Criterion 5: View Mode
    if preferences.get("sidebarViewMode", "") == expected_view:
        score += 16
        feedback_parts.append(f"View mode set to {expected_view}")
    else:
        feedback_parts.append("View mode NOT set correctly")

    # Criterion 6: VLM Trajectory Verification (anti-gaming / interaction proof)
    vlm_points = 0
    if VLM_AVAILABLE:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            
            vlm_result = query_vlm(images=frames + [final_frame], prompt=VLM_PROMPT)
            if vlm_result and vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("workflow_attempted", False):
                    vlm_points += 10
                    feedback_parts.append("VLM: Preferences interaction detected")
                if parsed.get("sidebar_interaction", False):
                    vlm_points += 10
                    feedback_parts.append("VLM: Sidebar interaction detected")
        except Exception as e:
            logger.warning(f"VLM verification skipped/failed: {e}")
            # If VLM fails, we give grace points if API was perfect to not unfairly penalize
            if score == 80:
                vlm_points = 20

    score += vlm_points

    # Success threshold: 80 points (meaning at least 4/5 API criteria + some VLM, or perfect API)
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }