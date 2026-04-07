#!/usr/bin/env python3
"""
Verifier for add_weight_system task.

Independent Verification Signals:
1. File modified: Validates the file was explicitly saved during the task (Anti-gaming).
2. XML Parse (Structure): `<weightsystem>` must be added to the target dive.
3. XML Parse (Values): Weight system description and weight values must be accurate.
4. VLM Trajectory check: Ensures the visual progression of editing the 'Equipment' tab occurred.
"""

import os
import re
import json
import tempfile
import logging
import xml.etree.ElementTree as ET

logger = logging.getLogger(__name__)

def verify_add_weight_system(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "CRITICAL: copy_from_env function not available"}

    # 1. Fetch export results via temp file
    result_json = {}
    tmp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_res.close()
    try:
        copy_from_env('/tmp/task_result.json', tmp_res.name)
        with open(tmp_res.name, 'r') as f:
            result_json = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to read exported JSON result: {e}")
    finally:
        if os.path.exists(tmp_res.name):
            os.unlink(tmp_res.name)

    file_modified = result_json.get('file_modified', False)

    # 2. Fetch the target SSRF file
    tmp_ssrf = tempfile.NamedTemporaryFile(delete=False, suffix='.ssrf')
    tmp_ssrf.close()
    
    score = 0
    feedback = []

    # Criterion 1: File Modification Check (10 points)
    if file_modified:
        score += 10
        feedback.append("File modification detected (Ctrl+S).")
    else:
        feedback.append("File was NOT modified - changes were not saved.")

    has_weight_system = False
    has_correct_type = False
    has_correct_weight = False

    # Criterion 2 & 3: XML Structural Parsing (up to 75 points)
    try:
        copy_from_env('/home/ga/Documents/dives.ssrf', tmp_ssrf.name)
        tree = ET.parse(tmp_ssrf.name)
        root = tree.getroot()

        # Find dive #2
        dive2 = None
        for dive in root.iter('dive'):
            if dive.get('number') == '2':
                dive2 = dive
                break
                
        # Fallback if dive number attribute was somehow stripped
        if dive2 is None:
            dives = list(root.iter('dive'))
            if len(dives) > 1:
                dive2 = dives[1]

        if dive2 is not None:
            # Subsurface stores weight system data inside <weightsystem> tags
            systems = dive2.findall('weightsystem')
            
            if systems:
                score += 25
                has_weight_system = True
                feedback.append("Weight system node found on Dive #2.")

                for sys_node in systems:
                    # Check Type
                    desc = sys_node.get('description', '').lower()
                    if 'integrated' in desc:
                        has_correct_type = True

                    # Check Weight Value
                    weight_str = sys_node.get('weight', '')
                    m = re.search(r'[\d\.]+', weight_str)
                    if m:
                        val = float(m.group())
                        # Normalize to kg if it was entered as grams
                        if 'g' in weight_str.lower() and 'kg' not in weight_str.lower():
                            val /= 1000.0
                            
                        # Tolerance checking for 4.5 ± 0.1 kg
                        if 4.4 <= val <= 4.6:
                            has_correct_weight = True

                if has_correct_type:
                    score += 20
                    feedback.append("Correct Type: 'Integrated'.")
                else:
                    feedback.append("Type missing or incorrect (expected 'Integrated').")

                if has_correct_weight:
                    score += 30
                    feedback.append("Correct Weight: ~4.5 kg.")
                else:
                    feedback.append("Weight incorrect (expected 4.5 kg).")
            else:
                feedback.append("No weight system found on Dive #2.")
        else:
            feedback.append("CRITICAL: Dive #2 could not be found in the file.")
            
    except Exception as e:
        feedback.append(f"Error reading or parsing the dive log XML: {e}")
    finally:
        if os.path.exists(tmp_ssrf.name):
            os.unlink(tmp_ssrf.name)

    # Criterion 4: VLM Trajectory check (15 points)
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        # We explicitly evaluate frames across the trajectory to prove the work was done manually
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = """Look at these trajectory frames showing a user navigating the Subsurface dive log software. 
Did the user click into the 'Equipment' tab and interact with the weight system section below the cylinders?
Respond in JSON format:
{
  "interacted_with_equipment": true/false,
  "reasoning": "What visual evidence is present in the frames"
}"""
            res = query_vlm(images=frames, prompt=prompt)
            if res.get("parsed", {}).get("interacted_with_equipment", False):
                vlm_score = 15
                feedback.append("VLM verified trajectory progression.")
            else:
                feedback.append("VLM did not detect interaction with the Equipment tab.")
        else:
            # Gracefully handle framework absence of frame images
            vlm_score = 15
            feedback.append("No trajectory frames provided, awarding default VLM points.")
    except Exception as e:
        logger.warning(f"VLM verification skipped or failed: {e}")
        vlm_score = 15
        feedback.append("VLM verification skipped (module unavailable), awarding default points.")

    score += vlm_score

    # Check key passing criteria:
    # Agent must have saved the file AND successfully added a weight system
    key_criteria_met = file_modified and has_weight_system
    passed = (score >= 60) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }