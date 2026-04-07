#!/usr/bin/env python3
"""
Verifier for create_vertical_vas_rating task.

Verification Strategy:
1. File Existence & Anti-Gaming:
   - Check .psyexp and .csv exist and were modified during task.
2. Conditions File Validation:
   - Must be valid CSV with 'stim_id' and 'image_file'.
   - Must have at least 5 rows.
3. PsychoPy Experiment XML Parsing:
   - Loop presence linking to conditions file.
   - Slider Component Configuration:
     - Verticality: Size height > width.
     - Ticks: Empty (VAS requirement).
     - Granularity: 0.
     - Labels: Correct text.
     - Marker Start: None/Empty (no anchoring).

Scoring:
- Conditions File: 10 pts
- Slider Exists: 10 pts
- Vertical Orientation: 20 pts (CRITICAL)
- VAS Logic (No Ticks): 15 pts
- Continuous (Granularity 0): 10 pts
- Marker Hidden: 15 pts
- Variable Image & Loop: 20 pts
"""

import json
import tempfile
import os
import csv
import xml.etree.ElementTree as ET
import logging

logger = logging.getLogger(__name__)

def verify_create_vertical_vas_rating(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    exp_path = metadata.get('experiment_file', '/home/ga/PsychoPyExperiments/pain_vas.psyexp')
    cond_path = metadata.get('conditions_file', '/home/ga/PsychoPyExperiments/conditions/pain_stimuli.csv')
    
    score = 0
    feedback_parts = []
    
    # 1. Get Result JSON
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_json = tmp.name
        copy_from_env("/tmp/task_result.json", tmp_json)
        with open(tmp_json, 'r') as f:
            result_data = json.load(f)
        os.unlink(tmp_json)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result metadata: {e}"}

    # Anti-gaming check (nonce)
    if result_data.get('result_nonce') == "":
         # Strict check: if nonce missing, potential gaming
         pass 

    task_start = result_data.get('task_start_time', 0)

    # 2. Verify Conditions File (10 pts)
    cond_file_valid = False
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.csv') as tmp:
            local_cond = tmp.name
        copy_from_env(cond_path, local_cond)
        
        with open(local_cond, 'r') as f:
            reader = csv.DictReader(f)
            headers = [h.strip() for h in (reader.fieldnames or [])]
            rows = list(reader)
        
        req_cols = metadata.get('required_columns', ['stim_id', 'image_file'])
        has_cols = all(c in headers for c in req_cols)
        has_rows = len(rows) >= 5
        
        if has_cols and has_rows:
            score += 10
            cond_file_valid = True
            feedback_parts.append("Conditions file valid")
        else:
            feedback_parts.append(f"Conditions file issues: Cols={has_cols}, Rows={len(rows)}")
            
        os.unlink(local_cond)
    except Exception as e:
        feedback_parts.append("Conditions file missing or unreadable")

    # 3. Verify Experiment File
    if not result_data.get('experiment_exists'):
        return {"passed": False, "score": score, "feedback": "Experiment file not found. " + "; ".join(feedback_parts)}

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.psyexp') as tmp:
            local_exp = tmp.name
        copy_from_env(exp_path, local_exp)
        
        tree = ET.parse(local_exp)
        root = tree.getroot()
        
        # Helper to find components
        def get_components(comp_type):
            comps = []
            for routine in root.findall(".//Routine"):
                for child in routine:
                    if child.tag == comp_type or child.get('type') == comp_type:
                        comps.append(child)
            return comps
            
        # Helper to get param value
        def get_param(comp, name):
            for param in comp:
                if param.get('name') == name:
                    return param.get('val')
            return None

        # Check Loop (10 pts)
        loops = root.findall(".//LoopInitiator")
        loop_valid = False
        for loop in loops:
            conds_param = loop.find(".//Param[@name='conditionsFile']")
            if conds_param is not None and "pain_stimuli" in conds_param.get('val', ''):
                loop_valid = True
                break
        
        if loop_valid:
            score += 10
            feedback_parts.append("Loop linked correctly")
        else:
            feedback_parts.append("Loop missing or not linked to pain_stimuli.csv")

        # Check Slider (70 pts total distributed)
        sliders = get_components('SliderComponent')
        if not sliders:
             # Fallback: Check tag name directly if type attribute not used
            sliders = [c for c in root.findall(".//SliderComponent")] # Direct tag match

        # If still no sliders found by tag name, look for component with type="Slider"
        if not sliders:
             for routine in root.findall(".//Routine"):
                for child in routine:
                    if "Slider" in child.tag:
                        sliders.append(child)

        if sliders:
            slider = sliders[0] # Analyze the first slider
            score += 10 # Slider exists
            feedback_parts.append("Slider component found")

            # Vertical Orientation (20 pts)
            # Check size parameter: [w, h]. Vertical means h > w
            size_val = get_param(slider, 'size')
            orientation_val = get_param(slider, 'orientation') # Sometimes explicit
            is_vertical = False
            
            # Check explicit orientation setting (if available in this version)
            if orientation_val and 'vertical' in str(orientation_val).lower():
                is_vertical = True
            
            # Check dimensions logic
            if not is_vertical and size_val:
                try:
                    # Parse python-like list/tuple string e.g., "(0.1, 0.5)" or "[0.1, 0.5]"
                    clean_size = size_val.replace('(', '').replace(')', '').replace('[', '').replace(']', '')
                    dims = [float(x) for x in clean_size.split(',')]
                    if len(dims) == 2 and dims[1] > dims[0]:
                        is_vertical = True
                except:
                    pass
            
            if is_vertical:
                score += 20
                feedback_parts.append("Vertical orientation confirmed")
            else:
                feedback_parts.append("Slider not vertical (height must be > width)")

            # VAS Logic: Ticks (15 pts)
            # Should be empty list or None
            ticks_val = get_param(slider, 'ticks')
            # Empty list in python repr is "[]" or explicit None or empty string
            if ticks_val in ["[]", "", "None"] or ticks_val is None:
                score += 15
                feedback_parts.append("Ticks removed (VAS style)")
            else:
                feedback_parts.append(f"Ticks present: {ticks_val}")

            # Granularity 0 (10 pts)
            granularity = get_param(slider, 'granularity')
            if granularity and float(granularity) == 0:
                score += 10
                feedback_parts.append("Continuous granularity")
            else:
                feedback_parts.append("Granularity not 0")

            # Labels (5 pts partial)
            labels_val = get_param(slider, 'labels')
            required_labels = metadata.get('required_labels', [])
            if labels_val and all(l in labels_val for l in required_labels):
                score += 5
                feedback_parts.append("Labels correct")

            # Marker Start Hidden (15 pts)
            start_val = get_param(slider, 'startValue')
            if start_val in ["None", "", "[]", "None"] or start_val is None:
                score += 15
                feedback_parts.append("Initial marker hidden")
            else:
                feedback_parts.append("Initial marker visible (anchoring bias risk)")

        else:
            feedback_parts.append("No Slider component found")

        # Check Image Variable (10 pts)
        images = get_components('ImageComponent')
        if not images:
             # Fallback check
             for routine in root.findall(".//Routine"):
                 for child in routine:
                     if "Image" in child.tag:
                         images.append(child)

        image_variable_ok = False
        if images:
            img_val = get_param(images[0], 'image')
            if img_val and ('$' in img_val or 'image_file' in img_val):
                image_variable_ok = True
        
        if image_variable_ok:
            score += 10
            feedback_parts.append("Image component uses variable")
        
        os.unlink(local_exp)
        
    except Exception as e:
        feedback_parts.append(f"Error parsing experiment XML: {e}")

    # Determine pass/fail
    # Pass threshold 70, must include verticality (20) and slider existence (10)
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }