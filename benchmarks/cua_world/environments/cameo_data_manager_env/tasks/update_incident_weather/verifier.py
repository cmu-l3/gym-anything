#!/usr/bin/env python3
"""
Verifier for update_incident_weather task.

Requires:
1. incident_update.csv to exist in Documents.
2. The CSV to contain correct weather data for the Ammonia Leak incident.
3. VLM verification of the workflow (navigation and entry).
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

# Import VLM utilities from framework
# (Assuming gym_anything.vlm is available in the python path)
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
except ImportError:
    # Fallback for testing/stubbing
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None
    def query_vlm(prompt, images): return {"success": False, "error": "VLM lib missing"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_incident_weather(traj, env_info, task_info):
    """
    Verify the incident weather update task.
    
    Scoring:
    - 30 pts: CSV file exists and was created during task.
    - 40 pts: Data accuracy (Wind Speed, Direction, Temp, Humidity).
    - 30 pts: VLM Verification of workflow.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # 1. Retrieve Result JSON from Windows Container
    # Windows path defined in export_result.ps1: C:\Users\Docker\AppData\Local\Temp\task_result.json
    # Note: Docker cp from Windows containers sometimes requires specific path handling.
    # We assume copy_from_env handles the abstraction or takes the absolute path.
    windows_result_path = r"C:\Users\Docker\AppData\Local\Temp\task_result.json"
    
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(windows_result_path, temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result json: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed to retrieve verification data. Did the export script run?"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []

    # 2. Check File Existence & Timestamp (30 pts)
    if result_data.get("output_exists", False):
        if result_data.get("file_created_during_task", False):
            score += 30
            feedback.append("CSV exported successfully.")
        else:
            score += 10
            feedback.append("CSV exists but timestamp indicates it might be old.")
    else:
        feedback.append("Incident export CSV not found.")

    # 3. Check Data Content (40 pts)
    # Expected values from metadata
    meta = task_info.get("metadata", {}).get("expected_values", {})
    exp_speed = meta.get("wind_speed", 8)
    exp_temp = meta.get("temperature", 82)
    exp_hum = meta.get("humidity", 65)
    
    content = result_data.get("output_content", {})
    # Note: content might be a dict or a string depending on PS export
    if isinstance(content, str):
        try:
            content = json.loads(content)
        except:
            content = {}

    if content:
        # Check Wind Speed
        val_speed = str(content.get("Wind Speed", "")).strip()
        if str(exp_speed) in val_speed:
            score += 10
        else:
            feedback.append(f"Wind Speed mismatch: expected {exp_speed}, got '{val_speed}'")

        # Check Temp
        val_temp = str(content.get("Air Temperature", content.get("Temperature", ""))).strip()
        if str(exp_temp) in val_temp:
            score += 10
        else:
            feedback.append(f"Temp mismatch: expected {exp_temp}, got '{val_temp}'")

        # Check Humidity
        val_hum = str(content.get("Relative Humidity", content.get("Humidity", ""))).strip()
        if str(exp_hum) in val_hum:
            score += 10
        else:
            feedback.append(f"Humidity mismatch: expected {exp_hum}, got '{val_hum}'")

        # Check Direction (Flexible check for SE or 135)
        val_dir = str(content.get("Wind Direction", "")).strip().upper()
        if "SE" in val_dir or "135" in val_dir:
            score += 10
        else:
            feedback.append(f"Wind Direction mismatch: expected SE/135, got '{val_dir}'")
    else:
        feedback.append("Exported CSV was empty or unparseable.")

    # 4. VLM Verification (30 pts)
    # Check if agent was actually in the Incidents module
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    
    if frames:
        prompt = """
        Analyze these screenshots of CAMEO Data Manager.
        1. Did the user navigate to the 'Incidents' or 'History' tab?
        2. Is the user entering weather data (wind, temp, humidity)?
        3. Did the user use the Export menu (File > Export)?
        
        Respond JSON: {"incidents_accessed": bool, "data_entry_visible": bool, "export_menu_used": bool}
        """
        
        vlm_res = query_vlm(prompt=prompt, images=frames + ([final_shot] if final_shot else []))
        
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("incidents_accessed"): score += 10
            if parsed.get("data_entry_visible"): score += 10
            if parsed.get("export_menu_used"): score += 10
        else:
            # Fallback if VLM fails: give partial credit if CSV is perfect
            if score >= 60:
                score += 20
                feedback.append("VLM unavailable, assuming workflow correct based on output.")

    # Final Pass Check
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }