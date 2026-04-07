#!/usr/bin/env python3
"""
Verifier for Hemodynamic Instability Monitoring Task

Verification Logic:
1. Programmatic: Checks if 3 devices were created and Vital Signs app launched (via logs/windows).
2. Programmatic: Checks if the status note exists and contains relevant clinical data (HR, BP).
3. VLM: Analyzes the final screenshot to read the actual numbers on the screen to verify
   the agent successfully manipulated the simulators to the target values.

Targets:
- HR: ~110 bpm (Tachycardia)
- BP: ~90 mmHg Systolic (Hypotension)
- Pump: Active (>10 mL/hr)
"""

import json
import os
import tempfile
import logging
import re
from typing import Dict, Any

# Import VLM utilities from the framework
try:
    from vlm_utils import query_vlm, get_final_screenshot
except ImportError:
    # Fallback/mock for local testing if needed
    def query_vlm(prompt, image=None, images=None):
        return {"success": False, "error": "VLM import failed"}
    def get_final_screenshot(traj):
        return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hemodynamic_instability(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Extract Data
    openice_running = result.get('openice_running', False)
    multiparam_created = result.get('multiparam_created', False)
    nibp_created = result.get('nibp_created', False)
    pump_created = result.get('pump_created', False)
    app_launched = result.get('app_launched', False)
    window_increase = result.get('window_increase', 0)
    note_exists = result.get('note_exists', False)
    note_content = result.get('note_content', "").lower()
    task_start = result.get('task_start', 0)
    note_mtime = result.get('note_mtime', 0)

    # 1. Basic Setup & Device Creation (30 pts)
    if openice_running:
        score += 5
    else:
        feedback_parts.append("OpenICE not running.")
    
    # Check for 3 distinct devices (via logs or window count proxy)
    # 3 devices + 1 app usually means at least +3 or +4 windows
    devices_found = 0
    if multiparam_created: devices_found += 1
    if nibp_created: devices_found += 1
    if pump_created: devices_found += 1
    
    if devices_found >= 3:
        score += 25
        feedback_parts.append("All 3 required devices detected in logs.")
    elif window_increase >= 3:
        # Fallback if logs missed exact names but windows appeared
        score += 20
        feedback_parts.append(f"Detected {window_increase} new windows (likely devices).")
    elif devices_found > 0:
        score += 10 * devices_found
        feedback_parts.append(f"Only found {devices_found}/3 devices.")
    else:
        feedback_parts.append("No devices detected.")

    # 2. App Launch (10 pts)
    if app_launched:
        score += 10
        feedback_parts.append("Vital Signs app launched.")
    else:
        feedback_parts.append("Vital Signs app not detected.")

    # 3. Documentation (20 pts)
    if note_exists and note_mtime > task_start:
        score += 10
        feedback_parts.append("Status note created.")
        
        # Check content for clinical values
        content_score = 0
        if "110" in note_content or "tachy" in note_content:
            content_score += 3
        if "90" in note_content or "hypo" in note_content:
            content_score += 3
        if "shock" in note_content:
            content_score += 4
        
        score += content_score
        if content_score > 0:
            feedback_parts.append("Status note contains clinical details.")
    elif note_exists:
         feedback_parts.append("Status note exists but timestamp invalid.")

    # 4. VLM Verification of Simulated Values (40 pts)
    # This is the critical part - did they actually SET the values?
    
    final_screenshot = get_final_screenshot(traj)
    vlm_score = 0
    
    if final_screenshot:
        prompt = """
        Analyze this screen from a medical software. 
        1. Are there vital signs or numbers visible?
        2. Look for a HEART RATE (HR, Pulse). Is it near 110? (Range 105-115)
        3. Look for a BLOOD PRESSURE (NIBP, Sys). Is the systolic near 90? (Range 85-95)
        4. Is there an INFUSION PUMP active (showing a rate like 10, 15, 20 mL/hr)?
        
        Return JSON:
        {
            "hr_visible": bool,
            "hr_value": int or null,
            "hr_in_range": bool,
            "bp_visible": bool,
            "bp_systolic_value": int or null,
            "bp_in_range": bool,
            "pump_active": bool
        }
        """
        
        vlm_res = query_vlm(prompt, image=final_screenshot)
        
        if vlm_res and vlm_res.get('success'):
            data = vlm_res.get('parsed', {})
            
            # HR Verification
            if data.get('hr_in_range', False):
                vlm_score += 15
                feedback_parts.append("VLM: Heart Rate confirmed in target range (105-115).")
            elif data.get('hr_visible'):
                feedback_parts.append(f"VLM: HR visible but {data.get('hr_value')} not in range.")
            else:
                feedback_parts.append("VLM: Heart Rate not clearly visible.")

            # BP Verification
            if data.get('bp_in_range', False):
                vlm_score += 15
                feedback_parts.append("VLM: Systolic BP confirmed in target range (85-95).")
            elif data.get('bp_visible'):
                feedback_parts.append(f"VLM: BP visible but {data.get('bp_systolic_value')} not in range.")
            else:
                feedback_parts.append("VLM: Blood Pressure not clearly visible.")
                
            # Pump Verification
            if data.get('pump_active', False):
                vlm_score += 10
                feedback_parts.append("VLM: Infusion Pump appears active.")
        else:
            # Fallback if VLM fails: check log flags as weak evidence
            feedback_parts.append("VLM analysis failed.")
            if result.get('log_has_110'):
                vlm_score += 5
                feedback_parts.append("Log contains '110' (fallback).")
            if result.get('log_has_90'):
                vlm_score += 5
                feedback_parts.append("Log contains '90' (fallback).")

    score += vlm_score

    # Final Pass Calculation
    # Must have devices created AND valid VLM verification of at least one parameter OR good note content
    passed = score >= 60 and openice_running and devices_found >= 2

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "devices_found": devices_found,
            "vlm_score": vlm_score,
            "note_exists": note_exists
        }
    }