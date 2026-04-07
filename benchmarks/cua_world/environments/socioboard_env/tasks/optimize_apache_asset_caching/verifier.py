#!/usr/bin/env python3
"""
Verifier for optimize_apache_asset_caching task.

Uses `copy_from_env` to retrieve test HTTP headers collected by `export_result.sh`.
Calculates a multi-criteria score checking server health, specific MIME type caching,
and protection of dynamic PHP content. Also employs VLM trajectory analysis to 
confirm the agent edited configuration files in the terminal.
"""

import os
import json
import re
import tempfile
import logging

# Import VLM utilities for trajectory verification
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def get_max_age(headers_text: str):
    """Parse HTTP headers string and extract Cache-Control max-age in seconds."""
    if not headers_text:
        return None
    # Matches 'Cache-Control: max-age=2592000' or 'Cache-Control: public, max-age=604800'
    match = re.search(r'(?i)cache-control:.*?max-age=(\d+)', headers_text)
    if match:
        return int(match.group(1))
    return None

def verify_apache_caching(traj, env_info, task_info):
    """
    Verify caching headers for images, css, js, and index.php.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve output JSON from environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # ====================================================================
    # Criterion 1: Apache Server Health (10 Points)
    # ====================================================================
    apache_active = result.get('apache_active', False)
    apache_syntax_ok = result.get('apache_syntax_ok', False)
    
    if apache_active and apache_syntax_ok:
        score += 10
        feedback_parts.append("Apache running/syntax OK")
    else:
        feedback_parts.append("Apache broken/not running")
        # Fail early if server is broken
        return {
            "passed": False, 
            "score": score, 
            "feedback": " | ".join(feedback_parts)
        }

    # ====================================================================
    # Caching Verification Logic
    # ====================================================================
    # Tolerances allow for slight approximations (e.g. 1 month as 30 vs 31 days)
    # 1 month ~ 2,592,000 to 2,678,400. We accept [2000000, 3000000].
    # 1 week ~ 604,800. We accept [500000, 700000].
    
    png_age = get_max_age(result.get('headers_png', ''))
    css_age = get_max_age(result.get('headers_css', ''))
    js_age = get_max_age(result.get('headers_js', ''))
    php_age = get_max_age(result.get('headers_php', ''))

    # Criterion 2: Image Caching (20 Points)
    if png_age and 2000000 <= png_age <= 3000000:
        score += 20
        feedback_parts.append(f"PNG caching correct ({png_age}s)")
    else:
        feedback_parts.append(f"PNG missing/incorrect cache (got {png_age}s)")

    # Criterion 3: CSS Caching (15 Points)
    if css_age and 500000 <= css_age <= 700000:
        score += 15
        feedback_parts.append(f"CSS caching correct ({css_age}s)")
    else:
        feedback_parts.append(f"CSS missing/incorrect cache (got {css_age}s)")

    # Criterion 4: JS Caching (15 Points)
    if js_age and 500000 <= js_age <= 700000:
        score += 15
        feedback_parts.append(f"JS caching correct ({js_age}s)")
    else:
        feedback_parts.append(f"JS missing/incorrect cache (got {js_age}s)")

    # Criterion 5: Dynamic Content Safe (20 Points) - CRITICAL ANTI-GAMING
    if php_age is None or php_age < 3600:
        score += 20
        feedback_parts.append("PHP dynamic content protected")
        php_safe = True
    else:
        feedback_parts.append(f"CRITICAL: PHP aggressively cached! ({php_age}s)")
        php_safe = False
        # Severe penalty for breaking the dynamic application by globally caching everything
        score = min(score, 40)

    # ====================================================================
    # Criterion 6: VLM Trajectory Evidence (20 Points)
    # ====================================================================
    vlm_points = 0
    if VLM_AVAILABLE and traj:
        frames = sample_trajectory_frames(traj, n=5)
        if frames:
            prompt = (
                "You are an evaluator analyzing an AI agent's trajectory. "
                "Did the agent use a terminal text editor (like nano, vim, or echo) "
                "to edit Apache configuration files (e.g. .conf or .htaccess)? "
                "Respond with a JSON object: {\"edited_config\": true/false, \"reasoning\": \"brief string\"}"
            )
            vlm_response = query_vlm(images=frames, prompt=prompt)
            if vlm_response and vlm_response.get('parsed', {}).get('edited_config') is True:
                vlm_points = 20
                score += vlm_points
                feedback_parts.append("VLM confirmed config edit")
            else:
                feedback_parts.append("VLM did not detect config editing")

    # Evaluate Pass condition
    # Requires Server Health + PHP Safe + At least Image and CSS/JS caching working
    key_criteria_met = (apache_active and apache_syntax_ok and php_safe)
    passed = (score >= 70) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "png_max_age": png_age,
            "css_max_age": css_age,
            "js_max_age": js_age,
            "php_max_age": php_age,
            "vlm_points": vlm_points
        }
    }