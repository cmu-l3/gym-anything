#!/usr/bin/env python3
"""
Verifier for Annotate Airway Management Events task.

Verification Logic:
1. Parse the output .vital file using vitaldb library.
2. Extract the 'Primus/CO2' track to establish ground truth Intubation/Extubation times.
   - Ground Truth Intubation: First time CO2 > 10 mmHg for > 10 seconds.
   - Ground Truth Extubation: Last time CO2 > 10 mmHg.
3. Extract events labeled 'INTUBATION' and 'EXTUBATION' from the file.
4. Compare agent's event timestamps to calculated ground truth.
"""

import json
import os
import sys
import tempfile
import logging
import numpy as np

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def install_vitaldb():
    """Ensure vitaldb library is installed."""
    try:
        import vitaldb
        return True
    except ImportError:
        logger.info("Installing vitaldb...")
        try:
            import subprocess
            subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "vitaldb"])
            return True
        except Exception as e:
            logger.error(f"Failed to install vitaldb: {e}")
            return False

def verify_airway_events(traj, env_info, task_info):
    """
    Verify the agent correctly annotated Intubation and Extubation events.
    """
    # 0. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    if not install_vitaldb():
        return {"passed": False, "score": 0, "feedback": "System error: Could not install required library (vitaldb)"}
    
    import vitaldb

    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: Windows path in container mapped to local path
        copy_from_env("C:\\Users\\Docker\\Documents\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check Basic Criteria
    if not result_data.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file 'annotated_case.vital' was not found."}
    
    if not result_data.get("file_created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "Output file was not modified during the task execution (Anti-gaming check)."}

    # 3. Retrieve and Parse Vital File
    temp_vital = tempfile.NamedTemporaryFile(delete=False, suffix='.vital')
    try:
        copy_from_env("C:\\Users\\Docker\\Documents\\annotated_case.vital", temp_vital.name)
        vf = vitaldb.VitalFile(temp_vital.name)
    except Exception as e:
        return {"passed": False, "score": 10, "feedback": f"Failed to parse the Vital file: {str(e)}"}
    finally:
        # We keep the file for a moment to process, cleanup happens at end of function usually, 
        # but here we rely on os.unlink later or let tempfile handle it if closed? 
        # NamedTemporaryFile delete=False means we must delete manually.
        pass

    # 4. Analyze CO2 Track for Ground Truth
    TRACK_NAME = "Primus/CO2"
    CO2_THRESHOLD = 10.0
    
    # Find the actual track name (might handle case sensitivity)
    available_tracks = vf.get_track_names()
    co2_track = next((t for t in available_tracks if "CO2" in t and "Primus" in t), None)
    
    if not co2_track:
        # Fallback search
        co2_track = next((t for t in available_tracks if "CO2" in t), None)
    
    if not co2_track:
        if os.path.exists(temp_vital.name): os.unlink(temp_vital.name)
        return {"passed": False, "score": 20, "feedback": "Could not find CO2 track in saved file to verify accuracy."}

    # Get samples
    co2_data = vf.get_track_samples(co2_track) # Returns numpy array
    dt = vf.get_track_dt(co2_track)
    
    # Calculate Ground Truth
    # Mask valid breaths
    is_breathing = co2_data > CO2_THRESHOLD
    
    # Intubation: Start of breathing
    # Find first index where breathing is true
    breathing_indices = np.where(is_breathing)[0]
    
    if len(breathing_indices) == 0:
        if os.path.exists(temp_vital.name): os.unlink(temp_vital.name)
        return {"passed": False, "score": 20, "feedback": "The recorded file contains no valid CO2 data (flatline)."}

    gt_intubation_idx = breathing_indices[0]
    gt_extubation_idx = breathing_indices[-1]
    
    gt_intubation_time = gt_intubation_idx * dt
    gt_extubation_time = gt_extubation_idx * dt

    logger.info(f"Ground Truth - Intubation: {gt_intubation_time:.1f}s, Extubation: {gt_extubation_time:.1f}s")

    # 5. Extract Agent's Events
    events = vf.events # List of {'name': str, 'onset': float}
    
    agent_intubation = None
    agent_extubation = None
    
    for evt in events:
        name = evt['name'].upper()
        if "INTUBATION" in name:
            agent_intubation = evt['onset']
        if "EXTUBATION" in name:
            agent_extubation = evt['onset']

    # 6. Score
    score = 10 # Base points for file existing
    feedback = []
    
    # Check Intubation
    if agent_intubation is not None:
        diff = abs(agent_intubation - gt_intubation_time)
        if diff <= 60:
            score += 45
            feedback.append(f"Intubation event correct (diff: {diff:.1f}s).")
        else:
            score += 10
            feedback.append(f"Intubation event found but inaccurate (diff: {diff:.1f}s, allowed: 60s).")
    else:
        feedback.append("Intubation event marker missing.")

    # Check Extubation
    if agent_extubation is not None:
        diff = abs(agent_extubation - gt_extubation_time)
        if diff <= 60:
            score += 45
            feedback.append(f"Extubation event correct (diff: {diff:.1f}s).")
        else:
            score += 10
            feedback.append(f"Extubation event found but inaccurate (diff: {diff:.1f}s, allowed: 60s).")
    else:
        feedback.append("Extubation event marker missing.")

    # Cleanup
    if os.path.exists(temp_vital.name):
        os.unlink(temp_vital.name)

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }