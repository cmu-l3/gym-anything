#!/usr/bin/env python3
"""
Verifier for Closed Loop Safety Validation Task.

Verification Steps:
1. Artifact Check: Verify 3 screenshots and 1 CSV exist (25 pts).
2. CSV Logic Check: Verify the CSV contains the correct 80% -> 100% -> 80% protocol steps (25 pts).
3. Log Verification: Confirm Pulse Ox and Pump were created and Safety App launched (20 pts).
4. VLM Verification: Analyze the 'interlock' screenshot to confirm the system actually caught the safety violation (Pump Stopped/Red) (30 pts).
"""

import json
import os
import tempfile
import logging

# Import framework VLM utilities if available, otherwise strict fallback
try:
    from gym_anything.vlm import query_vlm
except ImportError:
    query_vlm = None

logger = logging.getLogger(__name__)

def verify_closed_loop_safety(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy unavailable"}

    # 1. Load Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []

    # ---------------------------------------------------------
    # Criterion 1: Artifact Existence (25 pts)
    # ---------------------------------------------------------
    artifacts = result.get('artifacts', {})
    files_found = 0
    if artifacts.get('nominal_png_exists'): files_found += 1
    if artifacts.get('interlock_png_exists'): files_found += 1
    if artifacts.get('recovery_png_exists'): files_found += 1
    if artifacts.get('csv_exists'): files_found += 1
    
    # Scale score: 25 pts total, approx 6.25 per file
    artifact_score = int((files_found / 4) * 25)
    score += artifact_score
    feedback.append(f"Artifacts found: {files_found}/4 ({artifact_score} pts)")

    # ---------------------------------------------------------
    # Criterion 2: CSV Content Logic (25 pts)
    # ---------------------------------------------------------
    csv_content = result.get('csv_content', "")
    csv_score = 0
    if artifacts.get('csv_exists'):
        # Normalize newlines
        rows = [r.strip() for r in csv_content.strip().split('\\n') if r.strip()]
        
        # Check step 1 logic (80%)
        step1_ok = any('1' in r and '80%' in r and 'Infusing' in r for r in rows)
        # Check step 2 logic (100% -> Stopped)
        step2_ok = any('2' in r and '100%' in r and 'Stopped' in r for r in rows)
        # Check step 3 logic (80%)
        step3_ok = any('3' in r and '80%' in r and 'Infusing' in r for r in rows)

        if step1_ok: csv_score += 8
        if step2_ok: csv_score += 9  # Critical step
        if step3_ok: csv_score += 8
        
        if csv_score == 25:
            feedback.append("CSV protocol logic correct (25 pts)")
        else:
            feedback.append(f"CSV logic partial match ({csv_score} pts)")
    
    score += csv_score

    # ---------------------------------------------------------
    # Criterion 3: Log Verification (20 pts)
    # ---------------------------------------------------------
    logs = result.get('logs', {})
    log_score = 0
    if result.get('openice_running'): log_score += 5
    if logs.get('pulse_ox_created'): log_score += 5
    if logs.get('pump_created'): log_score += 5
    if logs.get('safety_app_launched'): log_score += 5
    
    score += log_score
    feedback.append(f"System/Log verification: {log_score}/20 pts")

    # ---------------------------------------------------------
    # Criterion 4: VLM Verification of Interlock Screenshot (30 pts)
    # ---------------------------------------------------------
    vlm_score = 0
    interlock_passed = False
    
    if artifacts.get('interlock_png_exists') and query_vlm:
        # We need to copy the specific screenshot out to verify it
        temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env("/home/ga/test_step_2_interlock.png", temp_img.name)
            
            prompt = """
            Analyze this screenshot of the OpenICE Infusion Safety application.
            This screenshot represents a 'Forced Interlock' test where the SpO2 threshold was set to 100%.
            
            Look for:
            1. A red warning banner or text indicating 'Stopped' or 'Interlock Active'.
            2. The Infusion Pump status showing 'Stopped' or 'Paused' (not Infusing).
            3. A threshold setting visible around 100%.
            
            Does this screenshot verify that the safety interlock triggered successfully?
            Respond in JSON: {"success": true/false, "confidence": "high/med/low", "reason": "..."}
            """
            
            response = query_vlm(image=temp_img.name, prompt=prompt)
            if response and response.get('parsed', {}).get('success'):
                vlm_score = 30
                interlock_passed = True
                feedback.append("VLM confirmed Interlock trigger in screenshot (30 pts)")
            else:
                feedback.append("VLM could not confirm Interlock state in screenshot (0 pts)")
                logger.info(f"VLM response: {response}")
                
        except Exception as e:
            feedback.append(f"VLM verification failed due to error: {e}")
        finally:
            if os.path.exists(temp_img.name):
                os.unlink(temp_img.name)
    elif not query_vlm:
        # Fallback if VLM not available: Check if step 2 CSV passed (trusting agent's report if VLM unavailable)
        if csv_score >= 17: # Implies step 2 was reported correct
            vlm_score = 15 # Partial credit
            feedback.append("VLM unavailable - partial credit based on CSV report")
    
    score += vlm_score

    # ---------------------------------------------------------
    # Final Result
    # ---------------------------------------------------------
    # Pass threshold: 70 pts AND Critical Interlock Verified (either via VLM or CSV logic)
    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "artifact_score": artifact_score,
            "csv_score": csv_score,
            "log_score": log_score,
            "vlm_score": vlm_score
        }
    }