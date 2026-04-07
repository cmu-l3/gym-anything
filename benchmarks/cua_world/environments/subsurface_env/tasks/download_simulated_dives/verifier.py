#!/usr/bin/env python3
"""Verifier for download_simulated_dives task."""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_download_simulated_dives(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    result_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_tmp.close()
    
    ssrf_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.ssrf')
    ssrf_tmp.close()

    try:
        # Load JSON result metadata
        try:
            copy_from_env('/tmp/task_result.json', result_tmp.name)
            with open(result_tmp.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not read task_result.json: {e}"}

        if not result.get('output_exists', False):
            return {"passed": False, "score": 0, "feedback": "dives.ssrf file does not exist."}
            
        file_modified = result.get('file_modified', False)
        
        # Parse SSRF XML
        try:
            copy_from_env('/home/ga/Documents/dives.ssrf', ssrf_tmp.name)
            tree = ET.parse(ssrf_tmp.name)
            root = tree.getroot()
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not parse dives.ssrf XML: {e}"}

        dives = list(root.iter('dive'))
        dive_count = len(dives)
        
        has_new_date = False
        has_simulator_model = False
        
        for dive in dives:
            date_str = dive.get('date', '')
            # Subsurface Simulator creates dives with system time (2026 based on prompt)
            if date_str and date_str >= "2020-01-01":
                has_new_date = True
                
            for dc in dive.iter('divecomputer'):
                model = dc.get('model', '').lower()
                if 'simulator' in model:
                    has_simulator_model = True
                    break

        score = 0
        feedback_parts = []
        
        # Validation 1: Anti-gaming (Do nothing)
        if file_modified:
            score += 10
            feedback_parts.append("File modified ✓")
        else:
            feedback_parts.append("File not modified ✗")
            
        # Validation 2: Did it add dives?
        if dive_count >= 9:
            score += 30
            feedback_parts.append(f"Dive count increased ({dive_count}) ✓")
        else:
            feedback_parts.append(f"Dive count not increased ({dive_count}) ✗")
            
        # Validation 3: Are the dives recent (proving simulator instead of duplicate)
        if has_new_date:
            score += 30
            feedback_parts.append("New date found ✓")
        else:
            feedback_parts.append("No new date found ✗")
            
        # Validation 4: Did it use Simulator model tag
        if has_simulator_model:
            score += 15
            feedback_parts.append("Simulator model tag found ✓")
        else:
            feedback_parts.append("No Simulator model tag found ✗")

        # Validation 5: VLM workflow confirmation
        try:
            from gym_anything.vlm import sample_trajectory_frames, query_vlm
            frames = sample_trajectory_frames(traj, n=5)
            if frames:
                prompt = (
                    "Look at these screenshots from a user session in Subsurface. "
                    "Did the user open and interact with the 'Download from dive computer' dialog? "
                    "Look for a window with 'Vendor' and 'Dive computer' dropdowns, and a 'Download' button. "
                    "Respond in JSON format: {\"download_dialog_used\": true/false}"
                )
                vlm_result = query_vlm(images=frames, prompt=prompt)
                
                download_dialog_used = False
                if isinstance(vlm_result, dict):
                    if 'parsed' in vlm_result and isinstance(vlm_result['parsed'], dict):
                        download_dialog_used = vlm_result['parsed'].get('download_dialog_used', False)
                    elif 'response' in vlm_result:
                        download_dialog_used = 'true' in str(vlm_result['response']).lower()
                elif isinstance(vlm_result, str):
                    download_dialog_used = 'true' in vlm_result.lower()
                    
                if download_dialog_used:
                    score += 15
                    feedback_parts.append("VLM confirmed download dialog ✓")
                else:
                    feedback_parts.append("VLM did not confirm download dialog ✗")
            else:
                feedback_parts.append("No trajectory frames available for VLM ✗")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            feedback_parts.append(f"VLM error")

        passed = score >= 70 and file_modified and dive_count >= 9 and has_new_date
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    finally:
        if os.path.exists(result_tmp.name):
            os.unlink(result_tmp.name)
        if os.path.exists(ssrf_tmp.name):
            os.unlink(ssrf_tmp.name)