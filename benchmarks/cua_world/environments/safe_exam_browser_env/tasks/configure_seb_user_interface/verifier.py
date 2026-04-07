#!/usr/bin/env python3
"""
Verifier for configure_seb_user_interface task.
Checks that SEB User Interface settings were configured correctly
in the exam configuration 'Certification Exam Fall 2024'.
"""

import json
import os
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_bool(val):
    """Normalize string/int representations of booleans to python bool."""
    if val is None:
        return None
    s = str(val).strip().lower()
    if s in ('true', '1', 'yes', 'on'):
        return True
    if s in ('false', '0', 'no', 'off'):
        return False
    return s

def verify_configure_seb_user_interface(traj, env_info, task_info):
    """
    Verify the SEB User Interface settings.
    Requires reading /tmp/task_result.json from the container.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # ================================================================
    # Extract results from container
    # ================================================================
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
    feedback = []
    
    # ================================================================
    # Check 1: Configuration Existence (10 points)
    # ================================================================
    if not result.get("config_exists", False):
        return {"passed": False, "score": 0, "feedback": "Configuration 'Certification Exam Fall 2024' not found in database."}
    
    score += 10
    feedback.append("Configuration exists (+10)")
    
    config_values = result.get("config_values", {})
    
    # Helper for case-insensitive/fuzzy attribute lookup
    def get_val(key_fragment):
        # Exact match first
        for k, v in config_values.items():
            if k == key_fragment: return v
        # Substring/case-insensitive match
        for k, v in config_values.items():
            if key_fragment.lower() in k.lower(): return v
        return None

    # ================================================================
    # Check 2: Values (15 points each)
    # ================================================================
    
    # 2.1 Browser View Mode = Window (15 points)
    # SEB often uses 1 for window, 0 for fullscreen, or strings.
    bvm = get_val("browserViewMode")
    if bvm is not None and str(bvm).strip().lower() in ('1', 'window', 'windowed', 'true'):
        score += 15
        feedback.append("Browser View Mode correctly set to Window (+15)")
    else:
        feedback.append(f"Browser View Mode incorrect (found: {bvm})")
        
    # 2.2 Show Task Bar = enabled (15 points)
    stb = normalize_bool(get_val("showTaskBar"))
    if stb is True:
        score += 15
        feedback.append("Show Task Bar enabled (+15)")
    else:
        feedback.append(f"Show Task Bar incorrect (found: {stb})")
        
    # 2.3 Task Bar Height = 44 (15 points)
    tbh = get_val("taskBarHeight")
    try:
        if tbh is not None and int(float(tbh)) == 44:
            score += 15
            feedback.append("Task Bar Height correctly set to 44 (+15)")
        else:
            feedback.append(f"Task Bar Height incorrect (found: {tbh})")
    except (ValueError, TypeError):
        feedback.append(f"Task Bar Height incorrect/invalid (found: {tbh})")
        
    # 2.4 Show Reload Button = disabled (15 points)
    srb = normalize_bool(get_val("showReloadButton"))
    if srb is False:
        score += 15
        feedback.append("Show Reload Button disabled (+15)")
    else:
        feedback.append(f"Show Reload Button incorrect (found: {srb})")
        
    # 2.5 Show Time = enabled (15 points)
    st = normalize_bool(get_val("showTime"))
    if st is True:
        score += 15
        feedback.append("Show Time enabled (+15)")
    else:
        feedback.append(f"Show Time incorrect (found: {st})")
        
    # 2.6 Show Keyboard Layout = disabled (15 points)
    # Usually called showInputLanguage in SEB schema
    sil = normalize_bool(get_val("showInputLanguage") or get_val("showKeyboardLayout"))
    if sil is False:
        score += 15
        feedback.append("Show Keyboard Layout disabled (+15)")
    else:
        feedback.append(f"Show Keyboard Layout incorrect (found: {sil})")

    # ================================================================
    # Check 3: Anti-Gaming
    # Ensure values were actually modified from baseline
    # ================================================================
    baseline = result.get("baseline", {})
    changes_detected = 0
    for key, current_val in config_values.items():
        if key in baseline and baseline[key] != current_val:
            changes_detected += 1
            
    if changes_detected == 0 and score > 25:
        # If no values changed from baseline at all, they didn't do the task.
        score = 0
        feedback.append("ANTI-GAMING: No configuration values were changed from baseline.")

    # ================================================================
    # Check 4: VLM Trajectory Verification
    # ================================================================
    try:
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        all_frames = frames + [final] if final else frames
        
        if all_frames:
            prompt = """
            Look at these frames from an agent completing a task in SEB Server.
            The task is to configure the 'User Interface' settings in an Exam Configuration.
            Do you see evidence that the agent:
            1. Navigated to Exam Configuration or SEB Settings
            2. Selected the 'User Interface' tab/section
            3. Modified form fields (dropdowns, checkboxes, or number inputs)
            
            Return JSON: {"evidence_found": true/false}
            """
            vlm_resp = query_vlm(images=all_frames, prompt=prompt)
            if vlm_resp and not vlm_resp.get('parsed', {}).get('evidence_found', False):
                feedback.append("VLM Verification: No visual evidence of User Interface configuration workflow.")
                # We don't fail outright if DB is perfect, but we flag it.
                score = max(0, score - 20)
    except Exception as e:
        logger.warning(f"VLM verification failed/skipped: {e}")

    # Pass threshold: 70
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "browserViewMode": bvm,
            "showTaskBar": stb,
            "taskBarHeight": tbh,
            "showReloadButton": srb,
            "showTime": st,
            "showInputLanguage": sil,
            "changes_from_baseline": changes_detected
        }
    }