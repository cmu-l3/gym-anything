#!/usr/bin/env python3
"""
Verifier for create_av_simultaneity_task.

Verification Strategy (Hybrid):
1. Programmatic Checks (70 pts):
   - Files exist and were created during task.
   - Conditions CSV: Check columns, row count, and data range (-0.3 to +0.3).
   - Experiment XML: Check visual start (0.5), Sound start (formula), Loop connection.
2. VLM Checks (30 pts):
   - Trajectory verification: Did the agent use the Builder interface?
   - Final state: Is the experiment flow visible?

Pass Threshold: 65 points.
"""

import json
import tempfile
import os
import csv
import xml.etree.ElementTree as ET
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logger = logging.getLogger(__name__)

def verify_create_av_simultaneity_task(traj, env_info, task_info):
    """Verify AV Simultaneity Task."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    exp_path = metadata.get('exp_file')
    cond_path = metadata.get('cond_file')
    
    score = 0
    feedback = []
    
    # 1. Load basic result info
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
            local_result_json = f.name
        copy_from_env("/tmp/task_result.json", local_result_json)
        with open(local_result_json) as f:
            basic_result = json.load(f)
        os.unlink(local_result_json)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}

    # 2. Verify Files Existence (10 pts)
    if basic_result.get('exp_exists') and basic_result.get('exp_modified'):
        score += 5
        feedback.append("Experiment file created.")
    else:
        feedback.append("Experiment file missing or not modified.")

    if basic_result.get('cond_exists') and basic_result.get('cond_modified'):
        score += 5
        feedback.append("Conditions file created.")
    else:
        feedback.append("Conditions file missing or not modified.")

    # 3. Analyze Conditions CSV (25 pts)
    csv_valid = False
    if basic_result.get('cond_exists'):
        try:
            with tempfile.NamedTemporaryFile(delete=False, suffix='.csv') as f:
                local_csv = f.name
            copy_from_env(cond_path, local_csv)
            
            with open(local_csv, 'r') as f:
                reader = csv.DictReader(f)
                rows = list(reader)
                headers = reader.fieldnames if reader.fieldnames else []
            
            os.unlink(local_csv)
            
            # Check columns
            if 'soa_offset' in headers and 'corrAns' in headers:
                score += 5
                feedback.append("CSV columns correct.")
                
                # Check rows and values
                if len(rows) >= 5:
                    score += 5
                    feedback.append(f"Row count sufficient ({len(rows)}).")
                    
                    offsets = []
                    try:
                        offsets = [float(r['soa_offset']) for r in rows if r['soa_offset'].strip()]
                    except ValueError:
                        feedback.append("Error parsing soa_offset values.")
                    
                    if offsets:
                        min_off = min(offsets)
                        max_off = max(offsets)
                        if min_off <= -0.3 and max_off >= 0.3:
                            score += 15
                            feedback.append(f"Offset range valid ({min_off} to {max_off}).")
                            csv_valid = True
                        else:
                            feedback.append(f"Offset range insufficient ({min_off} to {max_off}). Expected -0.3 to 0.3.")
                else:
                    feedback.append(f"Not enough rows ({len(rows)} < 5).")
            else:
                feedback.append(f"Missing required columns. Found: {headers}")

        except Exception as e:
            feedback.append(f"Failed to analyze CSV: {str(e)}")

    # 4. Analyze Experiment XML (35 pts)
    xml_valid = False
    if basic_result.get('exp_exists'):
        try:
            with tempfile.NamedTemporaryFile(delete=False, suffix='.psyexp') as f:
                local_exp = f.name
            copy_from_env(exp_path, local_exp)
            
            tree = ET.parse(local_exp)
            root = tree.getroot()
            os.unlink(local_exp)
            
            # Check for Loop
            loops = root.findall(".//LoopInitiator")
            loop_found = False
            for loop in loops:
                cond_param = loop.find(".//Param[@name='conditionsFile']")
                if cond_param is not None and "soa_conditions.csv" in cond_param.get('val', ''):
                    loop_found = True
                    break
            
            if loop_found:
                score += 10
                feedback.append("Loop correctly linked to conditions file.")
            else:
                feedback.append("Loop not found or not linked to soa_conditions.csv.")

            # Check Routines/Components
            visual_ok = False
            sound_ok = False
            
            # Find all routines
            routines = root.findall(".//Routine")
            for routine in routines:
                # Check Visual Component
                # Look for Polygon or Image or Text acting as flash
                for comp_type in ['PolygonComponent', 'ImageComponent', 'TextComponent', 'GratingComponent']:
                    # Just check all components in the routine, checking type by tag usually
                    # In .psyexp XML, components are children of Routine, tag name varies
                    for comp in routine:
                        # Check start time fixed at 0.5
                        start_param = comp.find("Param[@name='startVal']")
                        if start_param is not None:
                            val = start_param.get('val', '').strip()
                            if val == '0.5':
                                # Check if it's visual
                                if any(x in comp.tag for x in ['Polygon', 'Image', 'Grating', 'Text']):
                                    visual_ok = True

                        # Check Sound start time variable
                        if 'Sound' in comp.tag:
                            start_param = comp.find("Param[@name='startVal']")
                            if start_param is not None:
                                val = start_param.get('val', '').strip()
                                # Must contain 0.5 and soa_offset
                                if '0.5' in val and 'soa_offset' in val:
                                    sound_ok = True
                                    feedback.append(f"Sound timing correct: {val}")
                                else:
                                    feedback.append(f"Sound timing incorrect formula: {val}")

            if visual_ok:
                score += 10
                feedback.append("Visual stimulus starts at 0.5s.")
            else:
                feedback.append("Visual stimulus start time incorrect or not found.")

            if sound_ok:
                score += 15
                feedback.append("Sound stimulus timing uses variable offset.")
                xml_valid = True
            else:
                feedback.append("Sound stimulus timing incorrect.")

        except Exception as e:
            feedback.append(f"Failed to analyze XML: {str(e)}")

    # 5. VLM Verification (30 pts)
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=5)
        final_shot = get_final_screenshot(traj)
        
        prompt = """
        Analyze these screenshots of a user working in PsychoPy Builder.
        1. Do you see the PsychoPy Builder interface (flow chart at bottom, routine view at top)?
        2. Do you see any dialogs for setting component properties (e.g., Sound, Polygon)?
        3. Do you see a Conditions or Loop dialog?
        
        Answer with JSON:
        {
            "psychopy_visible": boolean,
            "component_dialog_visible": boolean,
            "flow_visible": boolean
        }
        """
        
        result = query_vlm(images=frames + [final_shot], prompt=prompt)
        parsed = result.get('parsed', {})
        
        if parsed.get('psychopy_visible'):
            vlm_score += 10
            feedback.append("VLM: PsychoPy interface detected.")
        if parsed.get('component_dialog_visible'):
            vlm_score += 10
            feedback.append("VLM: Component configuration detected.")
        if parsed.get('flow_visible'):
            vlm_score += 10
            feedback.append("VLM: Experiment flow detected.")
            
    except Exception as e:
        feedback.append(f"VLM verification failed: {e}")
    
    score += vlm_score

    # Final check
    # Must have valid XML logic for sound to pass
    passed = (score >= 65) and xml_valid and csv_valid

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }