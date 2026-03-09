#!/usr/bin/env python3
"""
Verifier for Confirmatory Factor Analysis (CFA) task.

CRITERIA:
1. Results text file exists and was created during the task.
2. Fit indices (CFI, TLI, RMSEA, SRMR) are parsed and within realistic ranges for the BFI-25 dataset.
3. Jamovi project file (.omv) exists and is not empty.
4. VLM verification of the workflow (CFA dialog usage).
"""

import json
import os
import sys
import tempfile
import base64
import re
import logging

# Add VLM utils to path
sys.path.append(os.path.join(os.path.dirname(__file__), '..', '..', 'scripts'))
try:
    from vlm_utils import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Mock for local testing if needed
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None
    def query_vlm(**kwargs): return {"success": False, "error": "VLM import failed"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cfa_analysis(traj, env_info, task_info):
    """
    Verify the CFA task completion.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    fit_ranges = metadata.get('fit_ranges', {
        "cfi_min": 0.70, "cfi_max": 0.90,
        "tli_min": 0.68, "tli_max": 0.88,
        "rmsea_min": 0.050, "rmsea_max": 0.100,
        "srmr_min": 0.050, "srmr_max": 0.120
    })

    score = 0
    feedback_parts = []
    
    # 1. READ RESULT JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. CHECK FILES EXISTENCE & TIMESTAMPS
    results_exists = result.get('results_exists', False)
    results_fresh = result.get('results_created_during_task', False)
    project_exists = result.get('project_exists', False)
    project_fresh = result.get('project_created_during_task', False)
    project_size = result.get('project_size_bytes', 0)

    if results_exists and results_fresh:
        score += 10
        feedback_parts.append("Results text file created.")
    else:
        feedback_parts.append("Results text file missing or old.")

    if project_exists and project_fresh and project_size > 5000:
        score += 10
        feedback_parts.append("Project file (.omv) saved.")
    else:
        feedback_parts.append("Project file missing/empty.")

    # 3. PARSE AND VALIDATE FIT INDICES
    content_b64 = result.get('results_content_b64', "")
    fit_data = {}
    valid_indices_count = 0
    
    if content_b64:
        try:
            content = base64.b64decode(content_b64).decode('utf-8')
            # Look for patterns like "CFI: 0.789" or "CFI 0.789" or "CFI=0.789"
            patterns = {
                "CFI": r"CFI[:=\s]+([0-9\.]+)",
                "TLI": r"TLI[:=\s]+([0-9\.]+)",
                "RMSEA": r"RMSEA[:=\s]+([0-9\.]+)",
                "SRMR": r"SRMR[:=\s]+([0-9\.]+)"
            }
            
            for name, pattern in patterns.items():
                match = re.search(pattern, content, re.IGNORECASE)
                if match:
                    try:
                        val = float(match.group(1))
                        fit_data[name] = val
                        
                        # Validate range
                        r_min = fit_ranges.get(f"{name.lower()}_min", 0)
                        r_max = fit_ranges.get(f"{name.lower()}_max", 1)
                        
                        if r_min <= val <= r_max:
                            score += 15
                            valid_indices_count += 1
                            feedback_parts.append(f"{name} OK ({val})")
                        else:
                            feedback_parts.append(f"{name} out of range ({val})")
                    except ValueError:
                        feedback_parts.append(f"{name} parse error")
                else:
                    feedback_parts.append(f"{name} not found")
                    
        except Exception as e:
            feedback_parts.append(f"Error parsing content: {e}")

    # 4. VLM TRAJECTORY VERIFICATION
    # Ensure they actually used the CFA dialog, not just typed numbers
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    
    if frames and final_shot:
        vlm_images = frames + [final_shot]
        
        prompt = """
        You are verifying a Jamovi statistics task. 
        Look at these screenshots in order.
        
        Did the user:
        1. Open a dataset (spreadsheet view visible)?
        2. Open the "Confirmatory Factor Analysis" configuration panel (Factor > CFA)?
        3. Assign variables to factors (Factor 1, 2, 3, etc.)?
        4. Produce a result table showing "Confirmatory Factor Analysis" or "Model Fit"?
        
        Answer JSON: {"cfa_dialog_seen": bool, "results_seen": bool, "confidence": float}
        """
        
        vlm_res = query_vlm(images=vlm_images, prompt=prompt)
        
        if vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('cfa_dialog_seen', False) or parsed.get('results_seen', False):
                score += 20
                feedback_parts.append("Visual verification passed.")
            else:
                feedback_parts.append("Visual verification failed (CFA workflow not observed).")
        else:
            # Fallback if VLM fails: award points if indices were correct (benefit of doubt)
            if valid_indices_count >= 3:
                score += 20
                feedback_parts.append("VLM unavailable, assumed pass based on correct data.")

    # FINAL CHECK
    # Total possible: 10 + 10 + 60 (15*4) + 20 = 100
    passed = (score >= 60) and (valid_indices_count >= 2)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }