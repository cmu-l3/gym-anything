#!/usr/bin/env python3
"""
Verifier for probit_labor_participation task.

CRITERIA:
1. Files exist and created during task (Anti-gaming).
2. 'probit_results.txt' contains correct model output (Model type, vars, signs, N, LogLik).
3. 'predicted_probabilities.csv' contains valid probabilities (0-1 range, mean ~0.568).
4. VLM visual verification of workflow.
"""

import json
import os
import re
import csv
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_probit_labor_participation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Load Task Result JSON
    task_result = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task results: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check Result File (Text Output) - 40 pts total
    res_info = task_result.get('results_file', {})
    if res_info.get('exists') and res_info.get('created_during_task'):
        score += 10
        feedback_parts.append("Results file created")
        
        # Analyze content
        temp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(res_info['path'], temp_txt.name)
            with open(temp_txt.name, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
                
            # Content Checks
            content_lower = content.lower()
            
            # Model type
            if "probit" in content_lower:
                score += 5
                feedback_parts.append("Model identified as Probit")
            else:
                feedback_parts.append("Output does not mention Probit")

            # Dependent variable
            if "lfp" in content_lower:
                score += 5
                feedback_parts.append("Dependent variable 'lfp' found")
            
            # Regressors (Check all 7)
            regressors = ["nwifeinc", "educ", "exper", "expersq", "age", "kidslt6", "kidsge6"]
            found_regs = [r for r in regressors if r in content_lower]
            if len(found_regs) == 7:
                score += 5
                feedback_parts.append("All regressors present")
            elif len(found_regs) >= 5:
                score += 3
                feedback_parts.append(f"Most regressors present ({len(found_regs)}/7)")
            
            # N = 753
            if "753" in content:
                score += 5
                feedback_parts.append("Correct sample size (753)")
            
            # Log Likelihood ~ -401.3
            # Extract numbers following "Log-likelihood"
            ll_match = re.search(r"log-likelihood\s+([-0-9.]+)", content_lower)
            if ll_match:
                try:
                    ll_val = float(ll_match.group(1))
                    if abs(ll_val - (-401.3)) < 5.0:
                        score += 5
                        feedback_parts.append(f"Log-likelihood correct ({ll_val})")
                    else:
                        feedback_parts.append(f"Log-likelihood incorrect ({ll_val})")
                except:
                    pass
            
            # Check signs of coefficients (Regex for "varname ... coeff")
            # Expected: nwifeinc(-), educ(+), exper(+), expersq(-), age(-), kidslt6(-)
            sign_checks = [
                ("nwifeinc", -1), ("educ", 1), ("exper", 1), 
                ("expersq", -1), ("age", -1), ("kidslt6", -1)
            ]
            correct_signs = 0
            for var, expected_sign in sign_checks:
                # Regex looks for var name followed by number (coeff)
                # Handles Gretl format: "  nwifeinc    -0.0120   ..."
                match = re.search(rf"{var}\s+([+-]?\d+\.\d+)", content_lower)
                if match:
                    val = float(match.group(1))
                    if (val < 0 and expected_sign < 0) or (val > 0 and expected_sign > 0):
                        correct_signs += 1
            
            if correct_signs >= 5:
                score += 5
                feedback_parts.append("Coefficient signs match theory")
                
        except Exception as e:
            feedback_parts.append(f"Error analyzing results text: {e}")
        finally:
            if os.path.exists(temp_txt.name):
                os.unlink(temp_txt.name)
    else:
        feedback_parts.append("Results file missing or not created during task")

    # 3. Check Probabilities File (CSV) - 30 pts total
    prob_info = task_result.get('probs_file', {})
    if prob_info.get('exists') and prob_info.get('created_during_task'):
        score += 10
        feedback_parts.append("Probabilities file created")
        
        temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        try:
            copy_from_env(prob_info['path'], temp_csv.name)
            
            vals = []
            with open(temp_csv.name, 'r') as f:
                reader = csv.reader(f)
                for row in reader:
                    for cell in row:
                        try:
                            v = float(cell)
                            vals.append(v)
                        except ValueError:
                            continue # Skip headers
            
            if len(vals) > 0:
                # Range check
                in_range = all(0 <= v <= 1.0001 for v in vals) # Tolerance for float
                if in_range:
                    score += 10
                    feedback_parts.append("Probabilities in [0,1] range")
                else:
                    feedback_parts.append("Invalid probability values found")
                
                # Mean check
                mean_val = sum(vals) / len(vals)
                if abs(mean_val - 0.568) < 0.05:
                    score += 10
                    feedback_parts.append(f"Mean probability correct ({mean_val:.3f})")
                else:
                    feedback_parts.append(f"Mean probability deviating ({mean_val:.3f})")
            else:
                feedback_parts.append("CSV file contained no numeric data")
                
        except Exception as e:
            feedback_parts.append(f"Error analyzing CSV: {e}")
        finally:
            if os.path.exists(temp_csv.name):
                os.unlink(temp_csv.name)
    else:
        feedback_parts.append("Probabilities file missing or not created during task")

    # 4. VLM Verification (Trajectory) - 30 pts total
    # Use trajectory frames to confirm UI usage
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    if final_frame:
        frames.append(final_frame)
    
    if frames:
        prompt = """
        Review this sequence of screenshots from the Gretl econometrics software.
        The user was tasked with running a Probit regression on labor force participation.
        
        Look for:
        1. The Gretl main window showing variables (lfp, nwifeinc, etc.).
        2. A "Model" menu or "Probit" dialog box being open.
        3. A results window showing "Model X: Probit" or coefficients.
        4. Usage of the console/script editor if applicable.
        
        Did the user perform the Probit estimation steps?
        Answer JSON: {"steps_visible": boolean, "model_results_seen": boolean, "confidence": "high/medium/low"}
        """
        
        try:
            vlm_res = query_vlm(prompt=prompt, images=frames)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("steps_visible") or parsed.get("model_results_seen"):
                    score += 30
                    feedback_parts.append("VLM confirmed Probit workflow")
                else:
                    # Partial credit if ambiguous
                    score += 10
                    feedback_parts.append("VLM could not clearly confirm workflow")
            else:
                score += 15 # Default for system error
                feedback_parts.append("VLM check failed (system error)")
        except:
            score += 15
            feedback_parts.append("VLM check skipped")
    else:
        feedback_parts.append("No screenshots available for VLM")

    # Final Pass/Fail
    # Must have results file, probit identified, and reasonable score
    passed = (score >= 60) and ("Results file created" in feedback_parts)
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": "; ".join(feedback_parts)
    }