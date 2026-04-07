#!/usr/bin/env python3
"""
Verifier for openvsp_component_buildup_sets task.

Checks:
  1. Output file exists and was created/modified during task
  2. Set 'Wing_Body' exists and contains Fuselage + Main Wing while excluding tails
  3. Set 'Empennage' exists and contains both tails while excluding Fuselage + Main Wing
  4. VLM verifies that the Set Manager dialog was opened and utilized (Anti-gaming check)
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_openvsp_sets(traj, env_info, task_info):
    result_file = task_info.get("metadata", {}).get("result_file", "/tmp/openvsp_sets_result.json")
    
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
    local_tmp = tempfile.mktemp(suffix=".json")
    try:
        copy_from_env(result_file, local_tmp)
        with open(local_tmp, "r") as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Result file not found or corrupted: {e}"}
    finally:
        if os.path.exists(local_tmp):
            os.unlink(local_tmp)

    score = 0
    feedback_parts = []

    # 1. Output file check
    if not data.get("file_exists", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output file eCRM-001_sets.vsp3 not found. Did you save to the correct path?"
        }
    
    if not data.get("file_modified", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output file was not modified during the task execution time."
        }
        
    score += 10
    feedback_parts.append("Output file exists and was modified (+10)")

    content = data.get("content", "")
    content = content.replace("\\n", "\n").replace("\\t", "\t")

    try:
        root = ET.fromstring(content)
    except ET.ParseError as e:
        return {"passed": False, "score": score, "feedback": f"Output file is not valid XML: {e}"}

    # Extract component IDs for logical mapping
    geom_ids = {'fuse': [], 'wing': [], 'horiz': [], 'vert': []}
    for geom in root.findall('.//Geom'):
        name_node = geom.find('Name')
        geom_id = geom.attrib.get('ID', '')
        if name_node is not None and geom_id:
            name = name_node.text.lower()
            if 'fuse' in name: geom_ids['fuse'].append(geom_id)
            elif 'horizontal' in name: geom_ids['horiz'].append(geom_id)
            elif 'vertical' in name: geom_ids['vert'].append(geom_id)
            elif 'wing' in name: geom_ids['wing'].append(geom_id)

    fuse_ids = set(geom_ids['fuse'])
    wing_ids = set(geom_ids['wing'])
    horiz_ids = set(geom_ids['horiz'])
    vert_ids = set(geom_ids['vert'])

    target_wingbody_ids = fuse_ids.union(wing_ids)
    target_empennage_ids = horiz_ids.union(vert_ids)

    # Extract all custom sets created
    sets_found = {}
    for set_node in root.findall('.//Set'):
        name_node = set_node.find('Name')
        if name_node is not None:
            set_name = name_node.text
            comp_ids = [c.text for c in set_node.findall('CompID')]
            sets_found[set_name] = set(comp_ids)

    # 2 & 3 & 4. Wing_Body Set Validation (40 points total)
    if 'Wing_Body' in sets_found:
        score += 15
        feedback_parts.append("Wing_Body set exists (+15)")
        wb_ids = sets_found['Wing_Body']
        
        if target_wingbody_ids and target_wingbody_ids.issubset(wb_ids):
            score += 15
            feedback_parts.append("Wing_Body contains Fuselage and Wing (+15)")
        else:
            feedback_parts.append("Wing_Body is missing required Fuselage or Wing components (+0)")
            
        if target_empennage_ids and target_empennage_ids.isdisjoint(wb_ids):
            score += 10
            feedback_parts.append("Wing_Body strictly isolates Empennage components (+10)")
        else:
            feedback_parts.append("Wing_Body incorrectly includes Tail components (+0)")
    else:
        feedback_parts.append("Wing_Body set NOT found (+0)")

    # 5 & 6 & 7. Empennage Set Validation (40 points total)
    if 'Empennage' in sets_found:
        score += 15
        feedback_parts.append("Empennage set exists (+15)")
        emp_ids = sets_found['Empennage']
        
        if target_empennage_ids and target_empennage_ids.issubset(emp_ids):
            score += 15
            feedback_parts.append("Empennage contains both Tail components (+15)")
        else:
            feedback_parts.append("Empennage is missing required Tail components (+0)")
            
        if target_wingbody_ids and target_wingbody_ids.isdisjoint(emp_ids):
            score += 10
            feedback_parts.append("Empennage strictly isolates Wing/Body components (+10)")
        else:
            feedback_parts.append("Empennage incorrectly includes Wing/Body components (+0)")
    else:
        feedback_parts.append("Empennage set NOT found (+0)")

    # 8. VLM Trajectory Verification for GUI usage (10 points)
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=5)
            if frames:
                prompt = '''You are verifying an OpenVSP agent.
Look at these trajectory frames.
Did the agent open the "Set Setup" or "Set" dialog window (the tool used to group/organize components into sets like 'Wing_Body')?
Return JSON:
{
    "used_set_manager": true/false,
    "reasoning": "Brief explanation"
}'''
                vlm_res = query_vlm(prompt=prompt, image=frames)
                if vlm_res.get('success'):
                    parsed = vlm_res.get('parsed', {})
                    if parsed.get('used_set_manager', False):
                        vlm_score = 10
                        feedback_parts.append("VLM confirms Set Setup was used (+10)")
                    else:
                        feedback_parts.append("VLM did not detect Set Setup usage (+0)")
                else:
                    feedback_parts.append("VLM query failed, skipping GUI check (+0)")
        except ImportError:
            feedback_parts.append("VLM library missing, skipping GUI check (+0)")
    
    score += vlm_score

    # To pass: needs at least 75 points (most of the programmatic XML logic correct)
    passed = score >= 75

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }