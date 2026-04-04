#!/usr/bin/env python3
"""
Verifier for determine_runaway_rpm task.

Verification Strategy:
1. Consistency Check (Primary):
   - The agent exports the simulation data (Power/Torque vs RPM).
   - The verifier calculates the physical zero-crossing (runaway speed) from this data.
   - The verifier checks if the agent's reported value in the text file matches this calculated value.
   - This ensures the agent actually ran the simulation and interpreted it correctly, regardless of minor geometric differences.

2. Existence Checks:
   - Project file created.
   - Data exported.
   - Report created.

3. Anti-Gaming:
   - Files must be created during the task window.
   - Data file must contain valid numerical data.
"""

import json
import os
import re
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_runaway_rpm(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result metadata
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_json.name)
        with open(temp_result_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task results: {str(e)}"}
    finally:
        if os.path.exists(temp_result_json.name):
            os.unlink(temp_result_json.name)

    score = 0
    feedback_parts = []
    
    # 1. Verify Project Creation (20 pts)
    if result.get('project_exists') and result.get('project_size_bytes', 0) > 1000:
        score += 20
        feedback_parts.append("Project file saved.")
    else:
        feedback_parts.append("Project file missing or empty.")

    # 2. Verify Data Export (25 pts)
    # We need to analyze the data file to calculate the zero crossing
    data_valid = False
    calculated_runaway_rpm = None
    
    if result.get('data_exists') and result.get('data_created_during_task'):
        temp_data_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env("/home/ga/Documents/projects/runaway_data.txt", temp_data_file.name)
            
            # Parse data
            rpm_values = []
            power_values = [] # Or Torque
            
            with open(temp_data_file.name, 'r') as f:
                lines = f.readlines()
            
            # Simple parser for whitespace/comma separated numbers
            # QBlade exports usually have a header line
            for line in lines:
                line = line.strip()
                if not line or line.startswith('#') or line.startswith('x') or re.match(r'^[A-Za-z]', line):
                    continue
                
                parts = re.split(r'[,\t\s]+', line)
                try:
                    # Assuming standard export: X-axis (RPM) is col 0, Y-axis (Power/Torque) is col 1
                    # Sometimes index is col 0. We try to find 2 floats.
                    nums = [float(p) for p in parts if p.replace('.','',1).replace('-','',1).isdigit()]
                    if len(nums) >= 2:
                        rpm_values.append(nums[0])
                        power_values.append(nums[1])
                except ValueError:
                    continue

            if len(rpm_values) > 5:
                data_valid = True
                score += 25
                feedback_parts.append(f"Simulation data exported ({len(rpm_values)} points).")
                
                # Calculate Zero Crossing
                # Find interval where Power goes from Positive to Negative
                # Or Negative to Positive (though Runaway implies P>0 -> P<0 typically for motoring)
                
                # Sort by RPM just in case
                sorted_pairs = sorted(zip(rpm_values, power_values))
                rpm_values = [x[0] for x in sorted_pairs]
                power_values = [x[1] for x in sorted_pairs]
                
                for i in range(len(rpm_values) - 1):
                    p1 = power_values[i]
                    p2 = power_values[i+1]
                    
                    if (p1 >= 0 and p2 < 0) or (p1 <= 0 and p2 > 0):
                        # Zero crossing found!
                        # Linear interpolation: y - y1 = m(x - x1)
                        # 0 - p1 = ( (p2 - p1) / (r2 - r1) ) * (rx - r1)
                        # rx = r1 - p1 * (r2 - r1) / (p2 - p1)
                        
                        r1 = rpm_values[i]
                        r2 = rpm_values[i+1]
                        
                        if p2 != p1:
                            calculated_runaway_rpm = r1 - p1 * (r2 - r1) / (p2 - p1)
                            break
                
                if calculated_runaway_rpm is not None:
                    feedback_parts.append(f"Physics Valid: Zero crossing found at {calculated_runaway_rpm:.2f} RPM.")
                    score += 20
                else:
                    feedback_parts.append("Physics Check Failed: No zero-crossing found in data range.")
            else:
                feedback_parts.append("Data file contained insufficient valid data points.")
                
        except Exception as e:
            feedback_parts.append(f"Error analyzing data file: {str(e)}")
        finally:
            if os.path.exists(temp_data_file.name):
                os.unlink(temp_data_file.name)
    else:
        feedback_parts.append("Simulation data file missing or not created during task.")

    # 3. Verify Reported Value (35 pts)
    if result.get('report_exists'):
        content = result.get('report_content', '')
        # Regex to find number after Runaway_RPM:
        match = re.search(r'Runaway_RPM:?\s*([-+]?[0-9]*\.?[0-9]+)', content, re.IGNORECASE)
        
        if match:
            reported_val = float(match.group(1))
            
            if calculated_runaway_rpm is not None:
                diff = abs(reported_val - calculated_runaway_rpm)
                tolerance = 2.0 # RPM
                
                if diff <= tolerance:
                    score += 35
                    feedback_parts.append(f"Reported RPM ({reported_val}) matches simulation data ({calculated_runaway_rpm:.2f}).")
                else:
                    score += 10 # Partial credit for reporting a format-correct number
                    feedback_parts.append(f"Reported RPM ({reported_val}) does not match simulation data ({calculated_runaway_rpm:.2f}).")
            else:
                # If we couldn't calculate it (e.g. data file issues), but they reported something reasonable?
                # Hard to verify without ground truth. 
                # We give small points for format.
                score += 10
                feedback_parts.append(f"Reported RPM ({reported_val}) found, but could not verify against data.")
        else:
            feedback_parts.append("Report file exists but format 'Runaway_RPM: <value>' not found.")
    else:
        feedback_parts.append("Report file missing.")

    # Pass logic
    passed = score >= 65 and calculated_runaway_rpm is not None

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }