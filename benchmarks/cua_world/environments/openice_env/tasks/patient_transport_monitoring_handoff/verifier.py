#!/usr/bin/env python3
"""
Verifier for Patient Transport Handoff Task in OpenICE.

Logic:
1. Verify Bedside Monitor (Multiparameter) was created (Log analysis).
2. Verify Transport Monitor (Pulse Ox) was created (Log analysis).
3. Verify Vital Signs App was used (Log/Window analysis).
4. Verify Handoff Overlap via VLM analysis of agent-provided screenshot.
   - Must show TWO device adapters active + Vital Signs app.
5. Verify Final Disconnection State (Programmatic):
   - Multiparameter window MUST be gone.
   - Pulse Ox window MUST be present.
   - Vital Signs app MUST be present.
6. Verify Documentation (Text file check).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm

logger = logging.getLogger(__name__)

def verify_patient_transport_handoff(traj, env_info, task_info):
    # 1. Setup Data Access
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Extract Data
    final_state = result.get("final_state", {})
    history = result.get("history_log", {})
    artifacts = result.get("artifacts", {})
    openice_running = result.get("openice_running", False)
    
    score = 0
    feedback = []

    # --- SCORING ---

    # Criterion 1: OpenICE Running (Critical)
    if not openice_running:
        return {"passed": False, "score": 0, "feedback": "FAIL: OpenICE application is not running."}

    # Criterion 2: Bedside Monitor Created (10 pts)
    if history.get("multiparameter_created", False):
        score += 10
        feedback.append("✓ Bedside Monitor created")
    else:
        feedback.append("✗ Bedside Monitor creation not detected in logs")

    # Criterion 3: Transport Monitor Created (10 pts)
    if history.get("pulse_ox_created", False):
        score += 10
        feedback.append("✓ Transport Monitor created")
    else:
        feedback.append("✗ Transport Monitor creation not detected in logs")

    # Criterion 4: Vital Signs App Used (10 pts)
    if history.get("vital_signs_launched", False) or final_state.get("vital_signs_window_present", False):
        score += 10
        feedback.append("✓ Vital Signs app launched")
    else:
        feedback.append("✗ Vital Signs app usage not detected")

    # Criterion 5: Overlap Screenshot Verification (20 pts)
    # Using VLM to check the content of the screenshot
    overlap_score = 0
    if artifacts.get("overlap_screenshot_exists", False):
        overlap_path = artifacts.get("overlap_screenshot_path")
        
        # Copy the image out for VLM
        temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env(overlap_path, temp_img.name)
            
            # VLM Prompt
            prompt = """
            Analyze this screenshot of the OpenICE medical software.
            I need to verify a 'handoff overlap' state.
            
            Look for:
            1. Two distinct 'Device Adapter' windows/panels active simultaneously.
               - Specifically a 'Multiparameter Monitor' and a 'Pulse Oximeter'.
            2. A 'Vital Signs' application window displaying data.
            
            Return JSON:
            {
                "two_devices_visible": boolean,
                "multiparameter_visible": boolean,
                "pulse_oximeter_visible": boolean,
                "vital_signs_app_visible": boolean,
                "confidence": "high/medium/low"
            }
            """
            vlm_resp = query_vlm(prompt=prompt, image=temp_img.name)
            
            if vlm_resp.get("success"):
                parsed = vlm_resp.get("parsed", {})
                if parsed.get("two_devices_visible", False) or (parsed.get("multiparameter_visible") and parsed.get("pulse_oximeter_visible")):
                    overlap_score += 20
                    feedback.append("✓ Overlap screenshot confirms dual monitoring")
                elif parsed.get("vital_signs_app_visible", False):
                    overlap_score += 10
                    feedback.append("⚠ Overlap screenshot shows app but missing second device")
                else:
                    feedback.append("✗ Overlap screenshot content invalid")
            else:
                # Fallback if VLM fails but file exists
                overlap_score += 5
                feedback.append("⚠ Overlap screenshot exists (VLM failed)")
        except Exception as e:
            feedback.append(f"✗ Failed to analyze overlap screenshot: {e}")
        finally:
            if os.path.exists(temp_img.name):
                os.unlink(temp_img.name)
    else:
        feedback.append("✗ Overlap screenshot not found")
    
    score += overlap_score

    # Criterion 6: Disconnection Executed (15 pts)
    # Multiparameter must be GONE at the end
    if not final_state.get("multiparameter_window_present", True):
        score += 15
        feedback.append("✓ Bedside Monitor successfully disconnected (window closed)")
    else:
        feedback.append("✗ Bedside Monitor window still present (failed to disconnect)")

    # Criterion 7: Continuity Maintained (10 pts)
    # Pulse Ox AND Vital Signs must be PRESENT at the end
    if final_state.get("pulse_ox_window_present", False) and final_state.get("vital_signs_window_present", False):
        score += 10
        feedback.append("✓ Continuity maintained (Transport Monitor & App active)")
    else:
        feedback.append("✗ Continuity failed (Transport Monitor or App missing at end)")

    # Criterion 8: Parallel Sequence (20 pts)
    # Logic: If we have proof of overlap (screenshot) AND proof of final state (Multi gone, Pulse present),
    # we infer the sequence was correct.
    if overlap_score >= 10 and not final_state.get("multiparameter_window_present", True) and final_state.get("pulse_ox_window_present", False):
        score += 20
        feedback.append("✓ Handoff sequence validated")
    else:
        feedback.append("✗ Handoff sequence invalid or incomplete")

    # Criterion 9: Documentation (5 pts)
    if artifacts.get("log_report_exists", False):
        content = artifacts.get("log_report_content", "").lower()
        if "overlap" in content and "disconnected" in content:
            score += 5
            feedback.append("✓ Log report valid")
        else:
            score += 2
            feedback.append("⚠ Log report exists but missing keywords")
    else:
        feedback.append("✗ Log report missing")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }