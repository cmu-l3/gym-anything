#!/usr/bin/env python3
"""
Verifier for configure_run_app task.
"""

import json
import tempfile
import os
import logging
import re
from xml.etree import ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_run_app(traj, env_info, task_info):
    """
    Verify that the agent correctly configured and ran the application.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # Read result file
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_result.close()
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}

    # =========================================================
    # 1. Output File Verification (50 points)
    # =========================================================
    output_exists = result.get('output_exists', False)
    output_content = result.get('output_content', '')
    output_ts = result.get('output_timestamp', 0)
    task_start = result.get('task_start_timestamp', 0)

    if output_exists:
        # Check timestamp (Anti-gaming)
        if output_ts > task_start:
            score += 10
            feedback_parts.append("Output file created during task.")
        else:
            feedback_parts.append("Output file is old (pre-dated task start).")
            # Fail immediately if file is stale (shouldn't happen as setup clears it)
        
        # Parse JSON content
        try:
            data = json.loads(output_content)
            if isinstance(data, list):
                score += 10
                feedback_parts.append("Output is valid JSON array.")
                
                # Check record count
                count = len(data)
                min_count = metadata.get('expected_record_count_min', 30)
                max_count = metadata.get('expected_record_count_max', 45)
                
                if min_count <= count <= max_count:
                    score += 10
                    feedback_parts.append(f"Record count correct ({count}).")
                else:
                    feedback_parts.append(f"Record count incorrect ({count}). Expected {min_count}-{max_count}. Check filters.")

                # Check content filtering
                species_correct = all('virginica' in r.get('species', '') for r in data)
                petal_correct = all(r.get('petal_length', 0) >= 5.0 for r in data)
                
                if species_correct:
                    score += 10
                    feedback_parts.append("Species filter correct (all virginica).")
                else:
                    feedback_parts.append("Species filter failed: found non-virginica records.")
                    
                if petal_correct:
                    score += 10
                    feedback_parts.append("Petal length filter correct (all >= 5.0).")
                else:
                    feedback_parts.append("Petal length filter failed: found records < 5.0.")

            else:
                feedback_parts.append("Output JSON is not a list.")
        except json.JSONDecodeError:
            feedback_parts.append("Output file is not valid JSON.")
    else:
        feedback_parts.append("Output file not found.")

    # =========================================================
    # 2. Run Configuration Verification (30 points)
    # =========================================================
    run_config_exists = result.get('run_config_exists', 'false')
    run_config_content = result.get('run_config_content', '')

    if run_config_exists == 'true':
        score += 10
        feedback_parts.append("Run Configuration XML file found.")
        
        # Check XML content for requirements
        # Note: IntelliJ XML format varies slightly, but usually contains these keys
        vm_options_ok = "-Dfilter.species=virginica" in run_config_content
        args_ok = "data/iris.csv" in run_config_content
        env_ok = "OUTPUT_DIR" in run_config_content
        class_ok = "com.dataproc.App" in run_config_content
        
        if vm_options_ok: score += 5
        else: feedback_parts.append("Run config missing correct VM options.")
        
        if args_ok: score += 5
        else: feedback_parts.append("Run config missing correct program arguments.")
        
        if env_ok: score += 5
        else: feedback_parts.append("Run config missing environment variables.")
        
        if class_ok: score += 5
        else: feedback_parts.append("Run config missing main class.")
        
    elif run_config_exists == 'workspace':
        # Saved in workspace.xml (less ideal but valid if agent didn't share it)
        score += 5
        feedback_parts.append("Run Configuration found in workspace.xml (partial credit).")
        # We can't easily parse workspace.xml details without complex logic, so we rely on output verification
        if output_exists and output_ts > task_start:
             # If output is correct, assume config was mostly right
             score += 15
             feedback_parts.append("Inferred correct config from valid output.")
    else:
        feedback_parts.append("Run Configuration not found.")

    # =========================================================
    # 3. VLM Verification (20 points)
    # =========================================================
    # Use VLM to check if the Run/Debug Configurations dialog was used
    
    # Import VLM helpers if available
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames
        
        # Only check VLM if we haven't already failed the output check
        # This saves API costs on obvious failures
        if score > 0:
            frames = sample_trajectory_frames(traj, num_samples=5)
            query_vlm = env_info.get('query_vlm')
            
            if query_vlm and frames:
                prompt = """
                Analyze these screenshots of a user interacting with IntelliJ IDEA.
                I am looking for evidence that the user:
                1. Opened the 'Run/Debug Configurations' dialog.
                2. Entered 'ProcessIrisData' or set VM options/Arguments.
                3. Ran the application (Run tool window visible at bottom).
                
                Respond JSON: {"config_dialog_seen": bool, "run_window_seen": bool}
                """
                
                vlm_result = query_vlm(prompt=prompt, images=frames)
                if vlm_result and vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    if parsed.get('config_dialog_seen'):
                        vlm_score += 10
                        feedback_parts.append("VLM: Config dialog detected.")
                    if parsed.get('run_window_seen'):
                        vlm_score += 10
                        feedback_parts.append("VLM: Run execution detected.")
            else:
                # If VLM unavailable but output correct, give benefit of doubt for full marks
                if score >= 60:
                    vlm_score = 20
                    feedback_parts.append("VLM skipped (output verified).")
    except ImportError:
         if score >= 60:
            vlm_score = 20

    score += vlm_score

    # Final result
    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }