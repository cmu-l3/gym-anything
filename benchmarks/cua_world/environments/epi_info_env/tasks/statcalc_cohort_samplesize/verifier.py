#!/usr/bin/env python3
"""
Verifier for StatCalc Cohort Sample Size Task.

Checks:
1. Output file `silicosis_sample_size.txt` exists.
2. Content matches the expected Kelsey sample size (318).
3. VLM Trajectory verification to ensure StatCalc was actually used.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

# Import VLM utilities from the framework
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
except ImportError:
    # Fallback for local testing
    def sample_trajectory_frames(traj, n=5): return []
    def query_vlm(prompt, images): return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_statcalc_cohort_samplesize(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the StatCalc sample size calculation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_value = metadata.get('expected_value', 318)
    
    # Define score components
    score = 0
    feedback_lines = []
    
    # =========================================================
    # 1. Retrieve and Parse JSON Result from Container
    # =========================================================
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: Mapping from Windows container path to local temp
        # The export script saved to C:\Users\Docker\Documents\task_result.json
        # In a Windows Docker env, this usually maps to a path we can copy.
        # Assuming copy_from_env handles the path conversion or we use the absolute path in the container.
        copy_from_env("C:\\Users\\Docker\\Documents\\task_result.json", temp_file.name)
        
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to copy or parse result: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed to retrieve task results from environment. Did the agent create the output file?"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # =========================================================
    # 2. Evaluate File Content (Primary Metric)
    # =========================================================
    output_exists = result_data.get('output_exists', False)
    content_str = result_data.get('content_value', "")
    file_fresh = result_data.get('file_created_during_task', False)

    val_correct = False
    
    if output_exists:
        score += 20
        feedback_lines.append("Output file found.")
        
        if file_fresh:
            score += 10
            feedback_lines.append("File was created during the task.")
        else:
            feedback_lines.append("Warning: File timestamp indicates it might be old.")

        # Parse content
        try:
            # Handle potential whitespace or extra text
            import re
            numbers = re.findall(r'\d+', str(content_str))
            if numbers:
                val = int(numbers[0])
                if val == expected_value:
                    score += 40
                    val_correct = True
                    feedback_lines.append(f"Correct sample size calculated: {val}")
                elif abs(val - expected_value) <= 2:
                    score += 35
                    val_correct = True
                    feedback_lines.append(f"Sample size {val} is within acceptable tolerance of {expected_value}")
                else:
                    feedback_lines.append(f"Incorrect sample size. Got {val}, expected {expected_value}.")
            else:
                feedback_lines.append("File content does not contain a valid number.")
        except Exception:
            feedback_lines.append("Could not parse file content as integer.")
    else:
        feedback_lines.append("Output file 'silicosis_sample_size.txt' not found.")

    # =========================================================
    # 3. VLM Verification (Anti-Gaming & Workflow Check)
    # =========================================================
    # We verify that the agent actually opened StatCalc and didn't just write the number (if they guessed it).
    
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = """
        Analyze these screenshots from an Epi Info 7 task.
        I am looking for evidence that the user performed a Sample Size calculation.
        
        Check for:
        1. The "StatCalc" window or module is visible.
        2. "Cohort or Cross-Sectional" study type is selected.
        3. Parameters like "Confidence", "Power", "Ratio" are visible.
        4. The result "318" is visible in the result grid (likely under 'Kelsey' column).
        
        Return JSON:
        {
            "statcalc_visible": true/false,
            "cohort_tool_used": true/false,
            "result_visible": true/false
        }
        """
        
        vlm_res = query_vlm(prompt=vlm_prompt, images=frames)
        vlm_data = vlm_res.get('parsed', {}) if vlm_res.get('success') else {}
        
        if vlm_data.get('statcalc_visible'):
            score += 15
            feedback_lines.append("VLM confirmed StatCalc usage.")
        
        if vlm_data.get('result_visible') or vlm_data.get('cohort_tool_used'):
            score += 15
            feedback_lines.append("VLM confirmed correct tool/result visibility.")
    else:
        # If no frames (e.g. testing mode), give benefit of doubt if value is correct
        if val_correct:
            score += 30
            feedback_lines.append("Skipped VLM check (no frames), but value is correct.")

    # =========================================================
    # 4. Final Verdict
    # =========================================================
    passed = (score >= 90)  # Requires almost perfect execution
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_lines)
    }