#!/usr/bin/env python3
import json
import os
import re
import base64
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_high_altitude_performance(traj, env_info, task_info):
    """
    Verifies the QBlade high altitude performance task.
    
    Criteria:
    1. Project file exists and is valid XML/WPA.
    2. Project contains two BEM simulations with correct densities (1.225 and 0.900).
    3. Report file exists and contains a power ratio consistent with physics (approx 0.735).
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    metadata = task_info.get('metadata', {})
    expected_ratio = metadata.get('expected_ratio', 0.7347)
    ratio_tolerance = metadata.get('ratio_tolerance', 0.05) # Allow 5% deviation

    # Load JSON result
    result_data = {}
    with tempfile.NamedTemporaryFile(suffix=".json") as f:
        try:
            copy_from_env("/tmp/task_result.json", f.name)
            f.seek(0)
            result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}

    score = 0
    feedback = []
    
    # 2. Verify Project File Structure (40 points)
    project_exists = result_data.get("project_exists", False)
    
    if project_exists:
        score += 10
        feedback.append("Project file saved.")
        
        # Analyze Project Content
        # QBlade .wpa files are XML. We scan for Simulation blocks and Density tags.
        try:
            with tempfile.NamedTemporaryFile(suffix=".wpa") as wpa_tmp:
                copy_from_env(result_data["project_path"], wpa_tmp.name)
                wpa_tmp.seek(0)
                content = wpa_tmp.read().decode('utf-8', errors='ignore')
                
                # Check for Simulation definitions
                # QBlade XML structure for BEM often looks like:
                # <BEMSimulation> ... <Name>Sim_SeaLevel</Name> ... <Density>1.225</Density> ... </BEMSimulation>
                # Using regex to be robust against version differences
                
                # Find all densities associated with simulations
                # This regex looks for Density tags near simulation names or just present in the file
                densities = re.findall(r'<Density>([\d\.]+)</Density>', content)
                names = re.findall(r'<Name>([^<]+)</Name>', content)
                
                # Check for Sea Level Density (1.225)
                has_sealevel = any(abs(float(d) - 1.225) < 0.01 for d in densities)
                if has_sealevel:
                    score += 15
                    feedback.append("Sea Level simulation configuration found (Density ~ 1.225).")
                else:
                    feedback.append("Missing Sea Level density configuration (1.225).")

                # Check for High Altitude Density (0.900)
                has_highalt = any(abs(float(d) - 0.900) < 0.01 for d in densities)
                if has_highalt:
                    score += 15
                    feedback.append("High Altitude simulation configuration found (Density ~ 0.900).")
                else:
                    feedback.append("Missing High Altitude density configuration (0.900).")
                    
        except Exception as e:
            feedback.append(f"Error analyzing project file: {str(e)}")
    else:
        feedback.append("Project file not found.")

    # 3. Verify Report Content (60 points)
    report_exists = result_data.get("report_exists", False)
    
    if report_exists:
        score += 10
        feedback.append("Report file created.")
        
        try:
            # Decode content
            b64_content = result_data.get("report_content_b64", "")
            report_text = base64.b64decode(b64_content).decode('utf-8')
            
            # Extract numbers
            # Expecting lines like: "Sea Level Max Power: 1500 kW"
            # We look for floating point numbers in the text
            floats = [float(x) for x in re.findall(r"([\d\.]+)", report_text)]
            
            # We need at least 2 power values to calculate a ratio
            # Or the user might have calculated the ratio themselves
            
            # Simple heuristic: Look for the calculated ratio in the text or calculate it from largest values
            # If the text explicitly contains a ratio near 0.73, give points
            
            ratio_found = False
            
            # Method A: Explicit Ratio in text
            for num in floats:
                if 0.70 <= num <= 0.77:
                    ratio_found = True
                    break
            
            # Method B: Calculate from power values found
            if not ratio_found and len(floats) >= 2:
                # Assuming the two largest numbers are the power values (kW often large)
                sorted_nums = sorted(floats, reverse=True)
                # Filter for reasonable power values (e.g., > 10) to avoid confusion with density/small nums
                power_candidates = [n for n in sorted_nums if n > 10]
                
                if len(power_candidates) >= 2:
                    p1 = power_candidates[0] # Sea level (higher)
                    p2 = power_candidates[1] # High alt (lower)
                    calc_ratio = p2 / p1
                    if abs(calc_ratio - expected_ratio) <= ratio_tolerance:
                        ratio_found = True
                        feedback.append(f"Verified power values imply correct physics ratio ({calc_ratio:.4f}).")
            
            if ratio_found:
                score += 50
                feedback.append("Report data confirms correct physical relationship (Power ratio ~ 0.735).")
            else:
                feedback.append("Report values do not match expected physics for 0.9/1.225 density ratio.")
                
        except Exception as e:
            feedback.append(f"Error parsing report: {str(e)}")
    else:
        feedback.append("Report file not found.")

    # 4. Anti-Gaming Check
    if not result_data.get("file_created_during_task", False) and project_exists:
        score = 0
        feedback.insert(0, "FAILURE: Project file timestamp indicates it was not created during this task.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }