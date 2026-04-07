#!/usr/bin/env python3
"""
Verifier for configure_gripper_contact_physics task.

A robotics researcher must configure sim-to-real physics properties:
1. Set contactMaterial for LEFT_PAD and RIGHT_PAD to "silicone"
2. Set contactMaterial for TARGET_OBJECT to "glass"
3. Add a ContactProperties node in WorldInfo linking "silicone" and "glass"
4. Set coulombFriction to 0.15 and bounce to 0.0.

Scoring (100 points total):
  - File exists and saved correctly: 10 points
  - Gripper Pad Materials = "silicone": 15 points
  - Target Object Material = "glass": 15 points
  - ContactProperties Node Created linking the materials: 20 points
  - coulombFriction = 0.15: 30 points
  - bounce = 0.0: 10 points

Pass threshold: 70 points
"""

import json
import re
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def extract_contact_material(content, def_name):
    """Finds the contactMaterial for a specific DEF node in a Webots world."""
    idx = content.find(f"DEF {def_name}")
    if idx == -1:
        return None
    
    # Extract the node block (approximate, sufficient for search)
    segment = content[idx:idx + 2000]
    # We look for the FIRST contactMaterial after the DEF declaration before another DEF
    # But since it might be nested, we just do a simple search bounded tightly.
    match = re.search(r'contactMaterial\s+"([^"]+)"', segment)
    if match:
        return match.group(1)
    return None

def verify_configure_gripper_contact_physics(traj, env_info, task_info):
    """
    Verify the physical configuration properties in the saved Webots .wbt file.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/slippery_grasp.wbt')
    expected_pad_mat = metadata.get('expected_pad_material', 'silicone')
    expected_obj_mat = metadata.get('expected_obj_material', 'glass')
    expected_fric = float(metadata.get('expected_friction', 0.15))
    expected_bounce = float(metadata.get('expected_bounce', 0.0))

    score = 0
    feedback_parts = []

    # Step 1: Read export metadata (for anti-gaming timestamps)
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_result.close()
    try:
        copy_from_env('/tmp/task_result.json', temp_result.name)
        with open(temp_result.name, 'r') as f:
            export_data = json.load(f)
        os.unlink(temp_result.name)
    except Exception as e:
        logger.warning(f"Could not load export data: {e}")
        export_data = {}

    if not export_data.get("file_created_during_task", True):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output file timestamp predates task start (anti-gaming check failed)."
        }

    # Step 2: Copy and parse the .wbt file
    wbt_file = tempfile.NamedTemporaryFile(delete=False, suffix='.wbt')
    wbt_file.close()
    wbt_content = None

    try:
        copy_from_env(output_path, wbt_file.name)
        with open(wbt_file.name, 'r', errors='replace') as f:
            wbt_content = f.read()
        os.unlink(wbt_file.name)
    except Exception as e:
        logger.warning(f"Could not copy .wbt file: {e}")
        try:
            os.unlink(wbt_file.name)
        except Exception:
            pass

    if not wbt_content or len(wbt_content) < 200:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file not found or empty at {output_path}. Did you File > Save World As?"
        }
    
    score += 10
    feedback_parts.append("File saved successfully")

    # Step 3: Check Pad Materials
    left_pad_mat = extract_contact_material(wbt_content, 'LEFT_PAD')
    right_pad_mat = extract_contact_material(wbt_content, 'RIGHT_PAD')
    
    if left_pad_mat == expected_pad_mat and right_pad_mat == expected_pad_mat:
        score += 15
        feedback_parts.append(f"Pad materials correctly set to '{expected_pad_mat}'")
    else:
        feedback_parts.append(f"Pad materials incorrect (LEFT_PAD='{left_pad_mat}', RIGHT_PAD='{right_pad_mat}')")

    # Step 4: Check Object Material
    obj_mat = extract_contact_material(wbt_content, 'TARGET_OBJECT')
    if obj_mat == expected_obj_mat:
        score += 15
        feedback_parts.append(f"Object material correctly set to '{expected_obj_mat}'")
    else:
        feedback_parts.append(f"Object material incorrect (TARGET_OBJECT='{obj_mat}')")

    # Step 5: Check ContactProperties definition
    # Find all ContactProperties blocks
    blocks = re.findall(r'ContactProperties\s*\{([^}]+)\}', wbt_content)
    
    found_link = False
    friction_correct = False
    bounce_correct = False
    actual_fric = None
    actual_bounce = None
    
    for block in blocks:
        # Extract materials in this block
        m1_match = re.search(r'material1\s+"([^"]+)"', block)
        m2_match = re.search(r'material2\s+"([^"]+)"', block)
        
        m1 = m1_match.group(1) if m1_match else ""
        m2 = m2_match.group(1) if m2_match else ""
        
        # Check if this block links our two materials
        if {expected_pad_mat, expected_obj_mat}.issubset({m1, m2}):
            found_link = True
            
            # Extract friction
            # Handles 'coulombFriction 0.15' or 'coulombFriction [ 0.15 ]'
            fric_match = re.search(r'coulombFriction\s*(?:\[\s*)?([\d.]+)', block)
            if fric_match:
                actual_fric = float(fric_match.group(1))
                if abs(actual_fric - expected_fric) < 0.01:
                    friction_correct = True
                    
            # Extract bounce
            bounce_match = re.search(r'bounce\s+([\d.]+)', block)
            if bounce_match:
                actual_bounce = float(bounce_match.group(1))
                if abs(actual_bounce - expected_bounce) < 0.01:
                    bounce_correct = True
            break
            
    if found_link:
        score += 20
        feedback_parts.append("ContactProperties links silicone and glass")
        
        if friction_correct:
            score += 30
            feedback_parts.append(f"Friction is correct ({expected_fric})")
        else:
            feedback_parts.append(f"Friction incorrect (found {actual_fric}, expected {expected_fric})")
            
        if bounce_correct:
            score += 10
            feedback_parts.append(f"Bounce is correct ({expected_bounce})")
        else:
            feedback_parts.append(f"Bounce incorrect (found {actual_bounce}, expected {expected_bounce})")
    else:
        feedback_parts.append("No ContactProperties node found linking 'silicone' and 'glass'")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }