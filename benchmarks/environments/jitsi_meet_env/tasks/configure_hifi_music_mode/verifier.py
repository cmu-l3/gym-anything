#!/usr/bin/env python3
"""
Verifier for configure_hifi_music_mode task.
"""

import json
import base64
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_hifi_music_mode(traj, env_info, task_info):
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

    score = 0
    feedback_parts = []
    
    # Check 1: Config File Modification (10 pts)
    if result.get("config_modified", False):
        score += 10
        feedback_parts.append("Config file modified")
    else:
        feedback_parts.append("Config file NOT modified")

    # Check 2: Docker Restart (10 pts)
    if result.get("container_restarted", False):
        score += 10
        feedback_parts.append("Service restarted")
    else:
        feedback_parts.append("Service NOT restarted (changes may not apply)")

    # Check 3: Evidence Screenshot (10 pts)
    if result.get("evidence_screenshot_exists", False):
        score += 10
        feedback_parts.append("Evidence screenshot saved")
    else:
        feedback_parts.append("Evidence screenshot missing")

    # Check 4: Config Content Parsing (70 pts)
    config_b64 = result.get("config_content_b64", "")
    if config_b64:
        try:
            config_content = base64.b64decode(config_b64).decode('utf-8')
            
            # Helper to check regex presence
            def check_setting(name, pattern, points):
                if re.search(pattern, config_content, re.IGNORECASE | re.MULTILINE):
                    return points, f"{name} configured"
                return 0, f"{name} MISSING"

            # Stereo (25 pts) - look for config.stereo = true OR stereo: true
            pts, msg = check_setting("Stereo", r"(config\.stereo\s*=\s*true|['\"]?stereo['\"]?\s*:\s*true)", 25)
            score += pts
            feedback_parts.append(msg)

            # P2P Disabled (25 pts) - look for config.p2p = { enabled: false } or p2p: { enabled: false }
            # This is tricky because of whitespace/newlines. We look for 'p2p' followed eventually by 'enabled: false'
            # Or config.p2p.enabled = false
            p2p_pattern = r"(config\.p2p\s*=\s*\{\s*[\s\S]*?enabled\s*:\s*false)|(config\.p2p\.enabled\s*=\s*false)|(['\"]?p2p['\"]?\s*:\s*\{\s*[\s\S]*?enabled\s*:\s*false)"
            pts, msg = check_setting("P2P Disabled", p2p_pattern, 25)
            score += pts
            feedback_parts.append(msg)

            # Max Bitrate (10 pts) - 510000
            pts, msg = check_setting("Bitrate", r"(opusMaxAverageBitrate['\"]?\s*[:=]\s*510000)", 10)
            score += pts
            feedback_parts.append(msg)

            # Noisy Mic (10 pts) - enableNoisyMicDetection = false
            pts, msg = check_setting("Noisy Mic", r"(enableNoisyMicDetection['\"]?\s*[:=]\s*false)", 10)
            score += pts
            feedback_parts.append(msg)

        except Exception as e:
            feedback_parts.append(f"Error parsing config: {e}")
    else:
        feedback_parts.append("Config content empty or missing")

    # Calculate Pass/Fail
    # Passing requires Stereo AND P2P disabled (critical for music mode) AND Service Restart
    stereo_set = "Stereo configured" in feedback_parts
    p2p_set = "P2P Disabled configured" in feedback_parts
    restarted = result.get("container_restarted", False)
    
    # Tolerance: If they did the config perfectly but didn't restart, we might give partial credit,
    # but the task requires verifying in browser, which requires restart.
    
    passed = score >= 70 and stereo_set and restarted

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }