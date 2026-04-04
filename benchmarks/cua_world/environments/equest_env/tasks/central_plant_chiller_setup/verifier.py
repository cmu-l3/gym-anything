#!/usr/bin/env python3
"""
Verifier for central_plant_chiller_setup task.

Verifies:
1. eQUEST project (.inp) file was modified/saved.
2. 'Primary CHW Loop' exists with correct Setpoint (44F).
3. 'Main Air-Cooled Chiller' exists with correct Efficiency (1.05 kW/ton) and Type.
4. Chiller is attached to the Loop.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# BDL Parser Helpers
def parse_bdl(content):
    """
    Simple BDL parser to extract objects and their properties.
    Returns a dict of {Object_Name: {Type: X, Props: {k:v}}}.
    
    BDL structure:
    "Obj Name" = TYPE
       PROP = VAL
       ...
       ..
    """
    objects = {}
    current_obj = None
    current_props = {}
    current_type = None

    lines = content.split('\n')
    
    # Regex for object definition: "Name" = TYPE
    obj_def_re = re.compile(r'^\s*"([^"]+)"\s*=\s*([A-Z0-9-]+)\s*')
    # Regex for property: KEY = VALUE or KEY = "VALUE"
    prop_re = re.compile(r'^\s*([A-Z0-9-]+)\s*=\s*(.+?)\s*(\.\.|$)') # .. is terminator for some commands but usually newlines work

    for line in lines:
        line = line.split('..')[0].strip() # Remove comments/terminators
        if not line:
            continue

        # Check for new object
        m_obj = obj_def_re.match(line)
        if m_obj:
            # Save previous object
            if current_obj:
                objects[current_obj] = {'type': current_type, 'props': current_props}
            
            current_obj = m_obj.group(1)
            current_type = m_obj.group(2)
            current_props = {}
            continue

        # Check for property
        if current_obj:
            m_prop = prop_re.match(line)
            if m_prop:
                key = m_prop.group(1)
                val = m_prop.group(2).strip('"').strip()
                current_props[key] = val

    # Save last object
    if current_obj:
        objects[current_obj] = {'type': current_type, 'props': current_props}

    return objects

def verify_central_plant_chiller_setup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_loop = metadata.get('expected_loop_name', 'Primary CHW Loop')
    expected_chiller = metadata.get('expected_chiller_name', 'Main Air-Cooled Chiller')
    
    # eQUEST stores efficiency as EIR (Energy Input Ratio) usually.
    # 1.05 kW/ton conversion:
    # 1 kW = 3412.14 Btu/h
    # 1 ton = 12000 Btu/h
    # EIR = (Power_Input_Btu) / (Cooling_Output_Btu)
    # EIR = (1.05 * 3412.14) / 12000 = 0.29856
    target_eir = 0.29856
    eir_tolerance = 0.005 # Allow rounding differences
    
    score = 0
    feedback = []
    
    # 1. Get JSON result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\Users\\Docker\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Check file modification
    if result_data.get('file_modified_during_task'):
        score += 10
        feedback.append("Project saved successfully.")
    else:
        feedback.append("Project NOT saved during task.")
        return {"passed": False, "score": 0, "feedback": "Project file not modified. Task requires saving work."}

    # 2. Get INP File
    temp_inp = tempfile.NamedTemporaryFile(delete=False, suffix='.inp')
    inp_content = ""
    try:
        copy_from_env("C:\\Users\\Docker\\task_result.inp", temp_inp.name)
        with open(temp_inp.name, 'r', encoding='latin-1') as f:
            inp_content = f.read()
    except Exception as e:
        return {"passed": False, "score": 10, "feedback": f"Failed to retrieve .inp file: {e}"}
    finally:
        if os.path.exists(temp_inp.name):
            os.unlink(temp_inp.name)

    # 3. Parse INP
    bdl_objects = parse_bdl(inp_content)
    
    # Verify Loop
    loop_obj = bdl_objects.get(expected_loop)
    if loop_obj:
        score += 20
        feedback.append(f"Loop '{expected_loop}' created.")
        
        if loop_obj['type'] == 'CIRCULATION-LOOP':
            if loop_obj['props'].get('TYPE') == 'CHILLED-WATER':
                score += 10
                feedback.append("Loop Type: CHILLED-WATER (Correct).")
            else:
                feedback.append(f"Loop Type: {loop_obj['props'].get('TYPE')} (Expected: CHILLED-WATER).")
            
            cool_t = loop_obj['props'].get('COOL-SET-T', '0')
            try:
                if abs(float(cool_t) - 44.0) < 0.5:
                    score += 10
                    feedback.append("Loop Setpoint: 44.0 F (Correct).")
                else:
                    feedback.append(f"Loop Setpoint: {cool_t} (Expected: 44.0).")
            except:
                feedback.append(f"Loop Setpoint invalid: {cool_t}.")
        else:
            feedback.append("Object exists but is not a CIRCULATION-LOOP.")
    else:
        feedback.append(f"Loop '{expected_loop}' NOT found.")

    # Verify Chiller
    chiller_obj = bdl_objects.get(expected_chiller)
    if chiller_obj:
        score += 20
        feedback.append(f"Chiller '{expected_chiller}' created.")
        
        if chiller_obj['type'] == 'CHILLER':
            # Check Type
            chiller_type = chiller_obj['props'].get('TYPE', '')
            # eQUEST might store as ELEC-AIR-COOLED or similar
            if 'AIR-COOLED' in chiller_type:
                score += 10
                feedback.append(f"Chiller Type: {chiller_type} (Correct).")
            else:
                feedback.append(f"Chiller Type: {chiller_type} (Expected: AIR-COOLED).")

            # Check Assignment (Loop)
            # In BDL, assignment is often in the Chiller prop: CHW-LOOP = "Primary CHW Loop"
            assigned_loop = chiller_obj['props'].get('CHW-LOOP', '')
            if assigned_loop == expected_loop:
                score += 10
                feedback.append("Chiller correctly attached to CHW Loop.")
            else:
                feedback.append(f"Chiller attached to '{assigned_loop}' (Expected: '{expected_loop}').")

            # Check Efficiency (EIR)
            found_eir = False
            eir_val = chiller_obj['props'].get('COOLING-EIR')
            
            if eir_val:
                try:
                    eir_float = float(eir_val)
                    if abs(eir_float - target_eir) < 0.01: # 0.298 ± 0.01
                        score += 10
                        feedback.append(f"Efficiency (EIR): {eir_float:.4f} (Matches 1.05 kW/ton).")
                        found_eir = True
                    else:
                        feedback.append(f"Efficiency (EIR): {eir_float:.4f} (Expected ~0.299 for 1.05 kW/ton).")
                except:
                    pass
            
            # Fallback: sometimes stored as specific KW/TON keyword in some versions
            if not found_eir:
                kw_ton_val = chiller_obj['props'].get('KW/TON') # Hypothetical keyword if BDL differs
                if kw_ton_val and abs(float(kw_ton_val) - 1.05) < 0.05:
                    score += 10
                    feedback.append(f"Efficiency (KW/TON): {kw_ton_val} (Correct).")
                    found_eir = True
            
            if not found_eir:
                feedback.append("Efficiency parameter incorrect or not found.")

        else:
            feedback.append("Object exists but is not a CHILLER.")
    else:
        feedback.append(f"Chiller '{expected_chiller}' NOT found.")

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " | ".join(feedback)
    }