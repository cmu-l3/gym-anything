#!/usr/bin/env python3
"""
Verifier for configure_high_fps_screenshare task.

Verifies:
1. config.js has correct desktopSharingFrameRate (min: 15, max: 30)
2. config.js has enableLayerSuspension: true
3. Jitsi web service is healthy (reachable)
4. Report file was created
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_high_fps_config(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Initialize scoring
    score = 0
    feedback_parts = []
    
    # 1. Load task result JSON
    task_result = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
        try:
            copy_from_env("/tmp/task_result.json", f.name)
            f.seek(0)
            task_result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
        finally:
            try:
                os.unlink(f.name)
            except:
                pass

    # Check basic health
    if task_result.get("web_reachable", False):
        score += 10
        feedback_parts.append("Jitsi Web UI is reachable")
    else:
        feedback_parts.append("Jitsi Web UI is NOT reachable (did you break the config?)")

    if task_result.get("report_exists", False):
        score += 10
        feedback_parts.append("Report file created")
    else:
        feedback_parts.append("Report file missing")

    # 2. Analyze config.js
    config_content = ""
    if task_result.get("config_exists", False):
        with tempfile.NamedTemporaryFile(delete=False, suffix='.js') as f:
            try:
                copy_from_env("/tmp/final_config.js", f.name)
                f.seek(0)
                config_content = f.read().decode('utf-8', errors='ignore')
            except Exception as e:
                feedback_parts.append(f"Failed to read config file: {e}")
            finally:
                try:
                    os.unlink(f.name)
                except:
                    pass
    else:
        feedback_parts.append("Config file not found")
        return {"passed": False, "score": score, "feedback": "; ".join(feedback_parts)}

    # Check for desktopSharingFrameRate
    # Look for patterns like: desktopSharingFrameRate: { min: 15, max: 30 }
    # Flexible regex to handle spacing and newlines
    fps_pattern = r"desktopSharingFrameRate\s*:\s*\{\s*min\s*:\s*(\d+)\s*,\s*max\s*:\s*(\d+)\s*\}"
    fps_match = re.search(fps_pattern, config_content)
    
    fps_correct = False
    if fps_match:
        min_fps = int(fps_match.group(1))
        max_fps = int(fps_match.group(2))
        
        if min_fps == 15:
            score += 20
            feedback_parts.append("Min FPS set correctly (15)")
        else:
            feedback_parts.append(f"Min FPS incorrect (found {min_fps}, expected 15)")

        if max_fps == 30:
            score += 20
            feedback_parts.append("Max FPS set correctly (30)")
        else:
            feedback_parts.append(f"Max FPS incorrect (found {max_fps}, expected 30)")
            
        if min_fps == 15 and max_fps == 30:
            fps_correct = True
    else:
        feedback_parts.append("desktopSharingFrameRate configuration not found or malformed")

    # Check for enableLayerSuspension
    # Pattern: enableLayerSuspension: true
    layer_pattern = r"enableLayerSuspension\s*:\s*(true|false)"
    layer_match = re.search(layer_pattern, config_content)
    
    if layer_match:
        val = layer_match.group(1)
        if val == "true":
            score += 20
            feedback_parts.append("Layer suspension enabled")
        else:
            feedback_parts.append("Layer suspension disabled")
    else:
        # Check if commented out? 
        feedback_parts.append("enableLayerSuspension setting not found")

    # Syntax check (Basic)
    # If the web interface is reachable (checked earlier), the syntax is likely valid.
    if task_result.get("web_reachable", False):
        score += 20
        feedback_parts.append("Config syntax valid (Service running)")
    else:
        feedback_parts.append("Service down - likely invalid config syntax")

    # Final verdict
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }