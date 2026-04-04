#!/usr/bin/env python3
"""
Verifier for nls_engel_curve task.
Checks if the agent successfully scripted and executed a Nonlinear Least Squares model.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_nls_engel_curve(traj, env_info, task_info):
    """
    Verify NLS task completion based on:
    1. Script file creation and content (syntax correctness)
    2. Output file creation and content (convergence, parameter values)
    3. Anti-gaming checks (timestamps)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_script_path = metadata.get('script_path', '/home/ga/Documents/gretl_output/nls_engel.inp')
    expected_output_path = metadata.get('output_path', '/home/ga/Documents/gretl_output/nls_engel_output.txt')
    gamma_min = metadata.get('gamma_min', 0.3)
    gamma_max = metadata.get('gamma_max', 2.5)

    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result Metadata
    # -------------------------
    try:
        temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_res.name)
        with open(temp_res.name, 'r') as f:
            task_result = json.load(f)
        os.unlink(temp_res.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task metadata: {str(e)}"}

    script_meta = task_result.get('script_file', {})
    output_meta = task_result.get('output_file', {})

    # 2. Verify Script File (30 points)
    # ---------------------------------
    if script_meta.get('exists') and script_meta.get('created_during_task'):
        score += 10
        
        # Analyze script content
        try:
            temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.inp')
            copy_from_env(expected_script_path, temp_script.name)
            with open(temp_script.name, 'r') as f:
                script_content = f.read().lower()
            os.unlink(temp_script.name)

            # Check for NLS syntax components
            if 'nls' in script_content and 'end nls' in script_content:
                score += 10
                feedback_parts.append("Script contains NLS block.")
            else:
                feedback_parts.append("Script missing 'nls'...'end nls' block.")

            if 'params' in script_content:
                score += 5
                feedback_parts.append("Script contains params declaration.")
            else:
                feedback_parts.append("Script missing 'params' keyword.")

            if 'outfile' in script_content:
                score += 5
                feedback_parts.append("Script uses 'outfile'.")
            else:
                feedback_parts.append("Script missing 'outfile' command.")

        except Exception as e:
            feedback_parts.append(f"Could not read script content: {e}")
    else:
        feedback_parts.append("Script file not created or timestamp invalid.")

    # 3. Verify Output File (70 points)
    # ---------------------------------
    if output_meta.get('exists') and output_meta.get('created_during_task'):
        # Base points for producing output
        score += 10
        
        if output_meta.get('size', 0) > 100:
            score += 10 # Content exists
            
            try:
                temp_out = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
                copy_from_env(expected_output_path, temp_out.name)
                with open(temp_out.name, 'r', errors='ignore') as f:
                    output_content = f.read()
                os.unlink(temp_out.name)

                # Check for convergence
                if re.search(r"Convergence achieved|Tolerance .* met", output_content, re.IGNORECASE):
                    score += 20
                    feedback_parts.append("NLS estimation converged.")
                elif "error" in output_content.lower():
                    feedback_parts.append("NLS estimation encountered errors.")
                else:
                    # Give partial points if we see parameter estimates even if exact convergence msg missing
                    if "coefficient" in output_content.lower():
                        score += 10
                        feedback_parts.append("Output contains coefficients (convergence uncertain).")

                # Parse Gamma parameter
                # Look for lines like: "gamma    0.85432    0.1234"
                # Regex matches: Name followed by number
                gamma_match = re.search(r"gamma\s+([+-]?\d*\.\d+)", output_content, re.IGNORECASE)
                
                if gamma_match:
                    try:
                        gamma_val = float(gamma_match.group(1))
                        if gamma_min <= gamma_val <= gamma_max:
                            score += 30
                            feedback_parts.append(f"Gamma estimate ({gamma_val:.4f}) is plausible.")
                        else:
                            score += 10 # Found, but value odd (maybe bad starting values)
                            feedback_parts.append(f"Gamma estimate ({gamma_val:.4f}) outside expected range.")
                    except ValueError:
                        feedback_parts.append("Could not parse gamma value.")
                else:
                    feedback_parts.append("Gamma parameter not found in output.")

            except Exception as e:
                feedback_parts.append(f"Error parsing output file: {e}")
        else:
            feedback_parts.append("Output file is empty.")
    else:
        feedback_parts.append("Output file not created or timestamp invalid.")

    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }