#!/usr/bin/env python3
import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_ini_string(content):
    """
    Parses a simple key=value format typical of Bridge Command INI files.
    Returns a dictionary with lowercase keys.
    """
    data = {}
    for line in content.split('\n'):
        line = line.strip()
        if not line or line.startswith('//') or line.startswith('#'):
            continue
        if '=' in line:
            parts = line.split('=', 1)
            key = parts[0].strip().lower()
            val = parts[1].strip()
            # Remove quotes if present
            if val.startswith('"') and val.endswith('"'):
                val = val[1:-1]
            data[key] = val
    return data

def verify_vlcc_model_calibration(traj, env_info, task_info):
    """
    Verifies the VLCC model configuration task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    specs = metadata.get('specs', {})
    
    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # --- CHECK 1: Model Existence & Basic Structure (15 pts) ---
    model_data = result.get('model', {})
    task_start = result.get('task_start', 0)
    boat_mtime = model_data.get('boat_file_mtime', 0)

    if model_data.get('exists'):
        score += 5
        feedback.append("Model directory created.")
    else:
        feedback.append("Model directory NOT found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    if model_data.get('boat_file_exists'):
        # Anti-gaming: Check timestamp
        if boat_mtime > task_start:
            score += 5
            feedback.append("boat.txt created during task.")
        else:
            feedback.append("boat.txt timestamp predates task (anti-gaming failure).")
    else:
        feedback.append("boat.txt NOT found.")

    if model_data.get('mesh_files_exist'):
        score += 5
        feedback.append("3D mesh files found.")
    else:
        feedback.append("No 3D mesh files (.x/.obj/.3ds) found in model dir.")

    # --- CHECK 2: boat.txt Content (50 pts) ---
    # Parse boat.txt
    boat_content = model_data.get('boat_file_content', '')
    boat_params = parse_ini_string(boat_content)
    
    param_score = 0
    param_checks = [
        ("Length", "length", 5),
        ("Beam", "beam", 5),
        ("Draft", "draft", 5),
        ("ShipMass", "shipmass", 5), # also check 'displacement'
        ("MaxSpeed", "maxspeed", 5),
        ("NumberOfEngines", "numberofengines", 5),
        ("MaxRudderAngle", "maxrudderangle", 5),
        ("RudderSpeed", "rudderspeed", 5),
        ("AsternEfficiency", "asternefficiency", 5),
        ("PropWalkAhead", "propwalkahead", 2.5),
        ("PropWalkAstern", "propwalkastern", 2.5)
    ]

    for spec_name, param_key, points in param_checks:
        spec = specs.get(spec_name, {})
        target = spec.get('target')
        tolerance = spec.get('tolerance')
        
        # Handle aliases (e.g., ShipMass vs Displacement)
        val_str = boat_params.get(param_key)
        if val_str is None and param_key == "shipmass":
            val_str = boat_params.get("displacement")
        
        if val_str is not None:
            try:
                val = float(val_str)
                if abs(val - target) <= tolerance:
                    param_score += points
                    feedback.append(f"{spec_name} correct ({val}).")
                else:
                    feedback.append(f"{spec_name} out of range (got {val}, want {target}±{tolerance}).")
            except ValueError:
                feedback.append(f"{spec_name} invalid number format.")
        else:
            feedback.append(f"{spec_name} missing from boat.txt.")

    # Check for vectors (Positions)
    # Simple check if keys exist, parsing vector string "x,y,z" is stricter
    if "gpsantenna" in boat_params:
        param_score += 2
    if "depthsounder" in boat_params:
        param_score += 1
    if "bridgeview" in boat_params:
        param_score += 2

    # Cap param score at 50
    score += min(param_score, 50)


    # --- CHECK 3: Scenario Configuration (25 pts) ---
    scenario_data = result.get('scenario', {})
    
    if scenario_data.get('exists'):
        score += 5
        feedback.append("Scenario directory created.")
        
        # Check ownship.ini references our model
        ownship_content = scenario_data.get('ownship_content', '')
        ownship_params = parse_ini_string(ownship_content)
        
        # The key for model type in ownship.ini is usually "Type" or "ShipModel"
        # In Bridge Command it's usually `Type="ModelName"`
        ship_type = ownship_params.get('type', '')
        if "vlcc_training" in ship_type.lower():
            score += 10
            feedback.append("Scenario uses correct custom model.")
        else:
            feedback.append(f"Scenario uses wrong model type: '{ship_type}'.")

        # Check traffic
        othership_content = scenario_data.get('othership_content', '')
        othership_params = parse_ini_string(othership_content)
        try:
            num_vessels = int(othership_params.get('number', 0))
            if num_vessels >= 2:
                score += 5
                feedback.append(f"Traffic vessels configured ({num_vessels}).")
            else:
                feedback.append(f"Insufficient traffic vessels ({num_vessels}).")
        except:
            feedback.append("Could not parse vessel count.")

        # Check environment
        if scenario_data.get('env_exists'):
            score += 5
            feedback.append("Environment configured.")
    else:
        feedback.append("Scenario directory NOT found.")


    # --- CHECK 4: Report (10 pts) ---
    report_data = result.get('report', {})
    if report_data.get('exists'):
        score += 10
        feedback.append("Report file created.")
        # Could add simple content check (length > 10 chars)
        if len(report_data.get('content', '')) < 20:
             feedback.append("Report content seems too short.")
    else:
        feedback.append("Report file NOT found.")

    # Calculate final result
    passed = (score >= 60) and model_data.get('boat_file_exists') and scenario_data.get('exists')

    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback)
    }