#!/usr/bin/env python3
"""
Verifier for extend_navigation_graph task.

Criteria:
1. SettingsFragment.kt exists and is a Fragment (20 pts)
2. fragment_settings.xml exists (20 pts)
3. nav_graph.xml contains 'settingsFragment' destination (20 pts)
4. nav_graph.xml contains 'action_home_to_settings' (20 pts)
5. HomeFragment.kt calls .navigate() (20 pts)
- Bonus/Penalty: Build success check (included in pass threshold logic)
"""

import json
import logging
import os
import re
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_extend_navigation_graph(traj, env_info, task_info):
    """Verify the implementation of the navigation graph extension."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result from the container
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
    
    # 1. Check SettingsFragment creation (20 pts)
    sf_content = result.get("settings_fragment_content", "")
    sf_exists = result.get("settings_fragment_exists", False)
    
    if sf_exists and "class SettingsFragment" in sf_content and "Fragment" in sf_content:
        score += 20
        feedback_parts.append("SettingsFragment created correctly")
    elif sf_exists:
        score += 10
        feedback_parts.append("SettingsFragment exists but content looks incomplete")
    else:
        feedback_parts.append("SettingsFragment.kt not found")

    # 2. Check Layout creation (20 pts)
    layout_exists = result.get("layout_exists", False)
    if layout_exists:
        score += 20
        feedback_parts.append("Layout file created")
    else:
        feedback_parts.append("fragment_settings.xml not found")

    # 3 & 4. Check Navigation Graph (40 pts total)
    nav_content = result.get("nav_graph_content", "")
    
    # Check destination
    if 'android:id="@+id/settingsFragment"' in nav_content or 'android:id="@id/settingsFragment"' in nav_content:
        score += 20
        feedback_parts.append("Destination added to graph")
    else:
        feedback_parts.append("settingsFragment destination missing in graph")

    # Check action
    if 'android:id="@+id/action_home_to_settings"' in nav_content or 'android:id="@id/action_home_to_settings"' in nav_content:
        # Verify it points to settings
        if 'app:destination="@id/settingsFragment"' in nav_content:
            score += 20
            feedback_parts.append("Action added correctly")
        else:
            score += 10
            feedback_parts.append("Action ID found but destination might be wrong")
    else:
        feedback_parts.append("action_home_to_settings missing in graph")

    # 5. Check Navigation Logic in HomeFragment (20 pts)
    hf_content = result.get("home_fragment_content", "")
    # Look for navigate call with correct ID
    if "R.id.action_home_to_settings" in hf_content and "navigate" in hf_content:
        score += 20
        feedback_parts.append("Navigation logic implemented in HomeFragment")
    elif "navigate" in hf_content:
        score += 10
        feedback_parts.append("Navigation call found but ID might be incorrect")
    else:
        feedback_parts.append("No navigation call found in HomeFragment")

    # Build Check (Pass/Fail condition modifier)
    build_success = result.get("build_success", False)
    if not build_success:
        feedback_parts.append("WARNING: Project build failed")
    
    # VLM Verification (Supplementary)
    # Using trajectory frames to confirm visual workflow (e.g. Nav Editor usage)
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, num_samples=5)
            
            prompt = """
            Does the user appear to be working in Android Studio?
            Do you see the Navigation Graph editor (a visual node graph)?
            Do you see code editing for a Fragment?
            """
            vlm_res = query_vlm(prompt=prompt, images=frames)
            if vlm_res.get('success'):
                vlm_score = 10 # Bonus for visual confirmation
        except:
            pass

    # Final logic
    passed = score >= 80 and build_success
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }