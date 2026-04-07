#!/usr/bin/env python3
"""
Verifier for Debug Drone Flight Log task.

Evaluates 5 distinct programmatic criteria by running the agent's updated pipeline
against a holdout dataset designed to highlight specific failure thresholds.
Includes code-level structural checks (AST-like) for robust partial credit,
preventing hardcoded "False" boolean gaming.

Incorporates VLM check via Trajectory imagery to verify VS Code usage.
"""

import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Safely import VLM components
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    logger.warning("gym_anything.vlm not available.")

VERIFICATION_PROMPT = """You are verifying if an AI agent successfully debugged a Python application in VS Code.
Look at these screenshots taken during the task.
1. Is VS Code open?
2. Did the agent open and edit Python files (like parser.py, geofence.py, or battery.py)?
3. Is there evidence of the agent modifying mathematical formulas, unit conversions, or logical conditions?

Respond strictly in JSON format:
{
    "vscode_used": true/false,
    "edited_python": true/false,
    "modified_logic": true/false,
    "confidence": "high/medium/low"
}
"""

def check_geo(res, src):
    val = res.get('geofence_breach')
    s = src.get('geofence.py', '')
    has_hav = any(k in s for k in ["haversine", "radians", "cos", "math.hypot"])
    
    if val is False and has_hav: return 16, "[+] Geofence evaluated correctly via holdout (Haversine/Trig used)"
    if has_hav: return 8, "[~] Partial: Haversine/Trig referenced but holdout output incorrect"
    if val is False: return 0, "[-] Failed: Output correct but no trig math found (Hardcoded gaming)"
    return 0, "[-] Geofence bug not fixed"

def check_alt(res, src):
    val = res.get('altitude_breach')
    s = src.get('parser.py', '')
    has_alt = "alt_rel" in s
    
    if val is False and has_alt: return 16, "[+] Altitude evaluated correctly via holdout (alt_rel used)"
    if has_alt: return 8, "[~] Partial: alt_rel referenced but holdout output incorrect"
    if val is False: return 0, "[-] Failed: Output correct but alt_rel not used (Hardcoded gaming)"
    return 0, "[-] Altitude bug not fixed"

def check_vib(res, src):
    val = res.get('max_vibration')
    s = src.get('parser.py', '')
    val_ok = isinstance(val, (int, float)) and abs(val - 1.732) < 0.05
    has_rms = any(k in s for k in ["sqrt", "pow(", "**", "hypot"])
    
    if val_ok and has_rms: return 16, "[+] Vibration RMS evaluated correctly via holdout"
    if has_rms: return 8, "[~] Partial: RMS math present but holdout output incorrect"
    if val_ok: return 0, "[-] Failed: Output correct but no RMS math found (Hardcoded gaming)"
    return 0, "[-] Vibration bug not fixed"

def check_bat(res, src):
    val = res.get('low_battery')
    s = src.get('battery.py', '')
    has_bat = "BATTERY_CELLS" in s
    
    if val is False and has_bat: return 16, "[+] Battery evaluated correctly via holdout (BATTERY_CELLS used)"
    if has_bat: return 8, "[~] Partial: BATTERY_CELLS referenced but holdout output incorrect"
    if val is False: return 0, "[-] Failed: Output correct but BATTERY_CELLS not used (Hardcoded gaming)"
    return 0, "[-] Battery bug not fixed"

def check_dur(res, src):
    val = res.get('duration_s')
    s = src.get('parser.py', '')
    val_ok = isinstance(val, (int, float)) and abs(val - 5.0) < 0.1
    has_conv = any(k in s for k in ["1000000", "1e6", "1_000_000"])
    
    if val_ok and has_conv: return 16, "[+] Duration evaluated correctly via holdout (Million conversion used)"
    if has_conv: return 8, "[~] Partial: 1,000,000 conversion present but holdout output incorrect"
    if val_ok: return 0, "[-] Failed: Output correct but conversion factor missing (Hardcoded gaming)"
    return 0, "[-] Duration bug not fixed"

def verify_drone_auditor(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    source_code = result.get('source_code', {})
    
    score = 0
    feedback_parts = []

    # 1. Evaluate 5 Logic Criteria
    pts, fb = check_geo(result, source_code); score += pts; feedback_parts.append(fb)
    pts, fb = check_alt(result, source_code); score += pts; feedback_parts.append(fb)
    pts, fb = check_vib(result, source_code); score += pts; feedback_parts.append(fb)
    pts, fb = check_bat(result, source_code); score += pts; feedback_parts.append(fb)
    pts, fb = check_dur(result, source_code); score += pts; feedback_parts.append(fb)

    # 2. Evaluate VLM Workflow trajectory
    query_vlm = env_info.get('query_vlm')
    images = []
    
    if VLM_AVAILABLE:
        try:
            frames = sample_trajectory_frames(traj, n=3)
            final = get_final_screenshot(traj)
            if frames: images.extend(frames)
            if final: images.append(final)
        except Exception as e:
            logger.warning(f"Error extracting trajectory frames: {e}")

    if query_vlm and images:
        try:
            vlm_res = query_vlm(prompt=VERIFICATION_PROMPT, images=images)
            parsed = vlm_res.get('parsed', {})
            
            if parsed.get('vscode_used') and parsed.get('edited_python'):
                score += 20
                feedback_parts.append("[+] VLM: Confirmed active Python code editing (20/20)")
            else:
                feedback_parts.append("[-] VLM: Insufficient visual evidence of Python editing (0/20)")
        except Exception as e:
            feedback_parts.append(f"[!] VLM verification encountered an error: {e}")
    else:
        feedback_parts.append("[!] VLM skipped: Provider or trajectory frames unavailable.")

    # Maximum achievable score: 100 (16 * 5 bugs + 20 VLM)
    # Passed >= 60
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }