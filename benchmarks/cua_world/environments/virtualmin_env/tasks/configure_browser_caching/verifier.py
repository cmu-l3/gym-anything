#!/usr/bin/env python3
"""
Verifier for configure_browser_caching task.

CRITERIA:
1. Apache `mod_expires` module must be enabled.
2. HTTP Headers for test asset must show caching (~30 days).
3. Configuration file should contain relevant directives.
4. Trajectory verification via VLM (ensure UI was used).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_browser_caching(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define constants
    EXPECTED_DURATION = 2592000  # 30 days in seconds
    TOLERANCE = 200000           # Allow some variance (e.g. 4 weeks vs 30 days vs 1 month)
    # 4 weeks = 2419200, 30 days = 2592000, 31 days = 2678400.
    # Accept range: 2,400,000 to 2,800,000

    score = 0
    feedback_parts = []
    
    # 1. Load result JSON
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

    # 2. Verify Module Enabled (25 pts)
    if result.get("module_enabled", False):
        score += 25
        feedback_parts.append("Apache expires module enabled.")
    else:
        feedback_parts.append("Apache expires module NOT enabled.")

    # 3. Verify HTTP Headers (Primary Success Criteria - 50 pts)
    max_age = int(result.get("http_max_age", 0))
    cache_control = result.get("cache_control_header", "")
    
    header_pass = False
    if 2400000 <= max_age <= 2800000:
        header_pass = True
        score += 50
        feedback_parts.append(f"HTTP Cache-Control correct (max-age={max_age}).")
    elif max_age > 0:
        score += 10
        feedback_parts.append(f"Caching enabled but duration incorrect (max-age={max_age}).")
    else:
        # Check Expires header fallback?
        # Typically Virtualmin sets Cache-Control, but if they set strict Expires...
        # We rely on max-age primarily.
        feedback_parts.append("HTTP Cache-Control header missing or invalid.")

    # 4. Verify Config Content (15 pts)
    # This checks if they actually edited the config, even if restart failed
    if result.get("config_contains_directive", False):
        score += 15
        feedback_parts.append("Configuration directives found.")
    else:
        feedback_parts.append("Configuration directives missing from virtual host.")

    # 5. VLM Verification (10 pts)
    # Check if they used the UI
    frames = sample_trajectory_frames(traj, n=4)
    final = get_final_screenshot(traj)
    
    vlm_prompt = (
        "The user is supposed to configure Apache settings in Virtualmin. "
        "Look for the 'Apache Webserver' module or 'Server Configuration' -> 'Website Options'. "
        "Do you see the user enabling modules or editing directives/options?"
    )
    
    vlm_res = query_vlm(images=frames + [final], prompt=vlm_prompt)
    if vlm_res.get("success") and vlm_res.get("parsed", {}).get("answer", False):
        score += 10
        feedback_parts.append("UI usage verified.")
    else:
        # Fallback points if programmatic worked perfectly
        if header_pass:
            score += 10 

    passed = (score >= 80) and header_pass

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }