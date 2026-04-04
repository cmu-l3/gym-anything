#!/usr/bin/env python3
"""
Verifier for annotate_hemodynamic_extremes task.
Checks if the user correctly identified Max HR and Min MAP events in the VitalDB recording.
"""

import json
import os
import sys
import tempfile
import logging
import time
import numpy as np

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import vitaldb, install if missing
try:
    import vitaldb
except ImportError:
    import subprocess
    logger.info("Installing vitaldb...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "vitaldb"])
    import vitaldb

def verify_annotate_hemodynamic_extremes(traj, env_info, task_info):
    """
    Verifies that the agent saved a .vital file with correct 'Max HR' and 'Min MAP' events.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Setup temporary paths
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    temp_vital_file = tempfile.NamedTemporaryFile(delete=False, suffix='.vital').name

    try:
        # 1. Retrieve result JSON from container
        try:
            copy_from_env("C:\\Users\\Docker\\AppData\\Local\\Temp\\task_result.json", temp_result_json)
            with open(temp_result_json, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}

        output_exists = result_data.get('output_exists', False)
        created_during_task = result_data.get('file_created_during_task', False)

        if not output_exists:
            return {"passed": False, "score": 0, "feedback": "Output file 'case_annotated.vital' not found."}
        
        if not created_during_task:
            return {"passed": False, "score": 0, "feedback": "Output file was not modified during the task."}

        # 2. Retrieve the .vital file to analyze events
        try:
            copy_from_env("C:\\Users\\Docker\\Documents\\case_annotated.vital", temp_vital_file)
        except Exception as e:
            return {"passed": False, "score": 10, "feedback": f"File exists but failed to copy for analysis: {str(e)}"}

        # 3. Analyze the vital file
        score = 20  # Base score for creating file
        feedback = ["File saved successfully."]
        
        try:
            vf = vitaldb.VitalFile(temp_vital_file)
            
            # Get Events
            events = vf.get_events() # List of {'name': str, 'dt': float}
            event_map = {e['name']: e['dt'] for e in events}
            
            # Check Max HR
            max_hr_score = 0
            if "Max HR" in event_map:
                agent_max_hr_time = event_map["Max HR"]
                
                # Calculate Ground Truth for Max HR
                # Case 1 usually has HR track named 'Solar8000/HR'
                hr_track_name = next((t for t in vf.get_track_names() if 'HR' in t), None)
                if hr_track_name:
                    # Get data
                    hr_data = vf.get_track_samples(hr_track_name, 1.0) # 1 sec interval
                    # Ignore 0s
                    valid_indices = np.where(hr_data > 0)[0]
                    if len(valid_indices) > 0:
                        true_max_idx = valid_indices[np.argmax(hr_data[valid_indices])]
                        true_max_time = true_max_idx * 1.0 # time in seconds
                        
                        diff = abs(agent_max_hr_time - true_max_time)
                        if diff <= 30.0:
                            max_hr_score = 40
                            feedback.append(f"Max HR event accurate (diff: {diff:.1f}s).")
                        elif diff <= 60.0:
                            max_hr_score = 20
                            feedback.append(f"Max HR event somewhat accurate (diff: {diff:.1f}s).")
                        else:
                            feedback.append(f"Max HR event inaccurate (diff: {diff:.1f}s).")
                    else:
                        feedback.append("Could not calculate ground truth HR (no valid data).")
                else:
                    feedback.append("HR track not found in file.")
            else:
                feedback.append("Event 'Max HR' missing.")

            # Check Min MAP
            min_map_score = 0
            if "Min MAP" in event_map:
                agent_min_map_time = event_map["Min MAP"]
                
                # Calculate Ground Truth for Min MAP
                map_track_name = next((t for t in vf.get_track_names() if 'ART_MBP' in t or 'ABP_MEAN' in t or 'MAP' in t), None)
                if map_track_name:
                    map_data = vf.get_track_samples(map_track_name, 1.0)
                    # Ignore artifacts (e.g. < 30 mmHg)
                    valid_indices = np.where(map_data > 30)[0]
                    if len(valid_indices) > 0:
                        true_min_idx = valid_indices[np.argmin(map_data[valid_indices])]
                        true_min_time = true_min_idx * 1.0
                        
                        diff = abs(agent_min_map_time - true_min_time)
                        if diff <= 30.0:
                            min_map_score = 40
                            feedback.append(f"Min MAP event accurate (diff: {diff:.1f}s).")
                        elif diff <= 60.0:
                            min_map_score = 20
                            feedback.append(f"Min MAP event somewhat accurate (diff: {diff:.1f}s).")
                        else:
                            feedback.append(f"Min MAP event inaccurate (diff: {diff:.1f}s).")
                    else:
                        feedback.append("Could not calculate ground truth MAP (no valid data > 30).")
                else:
                    feedback.append("MAP track not found in file.")
            else:
                feedback.append("Event 'Min MAP' missing.")

            score += max_hr_score + min_map_score

        except Exception as e:
            feedback.append(f"Error analyzing vital file: {e}")
            
        passed = score >= 65
        return {
            "passed": passed,
            "score": score,
            "feedback": " ".join(feedback)
        }

    finally:
        # Cleanup
        if os.path.exists(temp_result_json):
            os.remove(temp_result_json)
        if os.path.exists(temp_vital_file):
            os.remove(temp_vital_file)