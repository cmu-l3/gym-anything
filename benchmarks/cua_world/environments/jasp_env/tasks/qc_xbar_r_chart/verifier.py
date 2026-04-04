#!/usr/bin/env python3
"""
Verifier for qc_xbar_r_chart task.
Checks if the agent created a valid JASP project with the correct Quality Control analysis
and interpreted the results in a text report.
"""

import json
import os
import zipfile
import tempfile
import shutil
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_qc_xbar_r_chart(traj, env_info, task_info):
    """
    Verifies:
    1. JASP file created and contains QC analysis (programmatic)
    2. Report file created with "Status: In Control" or "Status: Out of Control"
    3. Visual verification of the chart
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_jasp_path = metadata.get('expected_jasp_file', '/home/ga/Documents/JASP/qc_analysis.jasp')
    
    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON
    task_result = {}
    with tempfile.NamedTemporaryFile(suffix='.json') as f:
        try:
            copy_from_env("/tmp/task_result.json", f.name)
            f.seek(0)
            task_result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}

    # 2. Verify JASP File Existence (10 pts)
    if not task_result.get('jasp_file_exists'):
        return {"passed": False, "score": 0, "feedback": "JASP project file was not created"}
    
    score += 10
    if task_result.get('jasp_created_during_task'):
        score += 10 # Created during task
    else:
        feedback_parts.append("Warning: File timestamp looks old")

    # 3. Analyze JASP File Content (40 pts)
    # JASP files are ZIPs containing analysis specifications in JSON/QML
    jasp_valid = False
    analysis_found = False
    params_correct = False
    
    temp_dir = tempfile.mkdtemp()
    try:
        local_jasp_path = os.path.join(temp_dir, "analysis.jasp")
        copy_from_env(expected_jasp_path, local_jasp_path)
        
        if zipfile.is_zipfile(local_jasp_path):
            with zipfile.ZipFile(local_jasp_path, 'r') as z:
                # Search for JSON files that might contain the analysis definition
                # JASP structure varies, but often has 'results/results.json' or similar
                json_files = [n for n in z.namelist() if n.endswith('.json')]
                
                for jf in json_files:
                    try:
                        data = json.loads(z.read(jf))
                        # Convert to string for loose searching to handle schema variations
                        data_str = json.dumps(data)
                        
                        # Check for QC module usage
                        if "QualityControl" in data_str or "XbarR" in data_str:
                            analysis_found = True
                            
                        # Check specific parameters
                        if '"E1"' in data_str and '"10"' in data_str:
                             params_correct = True
                             
                        # Stop if found
                        if analysis_found and params_correct:
                            break
                    except:
                        continue
            
            if analysis_found:
                score += 20
                feedback_parts.append("Quality Control analysis found in file")
            else:
                feedback_parts.append("Could not confirm QC analysis in JASP file")
                
            if params_correct:
                score += 20
                feedback_parts.append("Correct variable (E1) and subgroup size (10) detected")
            else:
                feedback_parts.append("Parameters (E1, size=10) not clearly found in file")
        else:
            feedback_parts.append("Saved file is not a valid JASP archive")

    except Exception as e:
        feedback_parts.append(f"Error analyzing JASP file: {str(e)}")
    finally:
        shutil.rmtree(temp_dir)

    # 4. Verify Report (20 pts)
    report_exists = task_result.get('report_exists', False)
    report_content = task_result.get('report_content', '').strip()
    
    if report_exists:
        score += 10
        feedback_parts.append("Report file exists")
        
        # We accept either status as long as it follows format, VLM will check truth
        if "In Control" in report_content or "Out of Control" in report_content:
            score += 10
            feedback_parts.append(f"Report format valid: '{report_content}'")
        else:
            feedback_parts.append(f"Report format invalid: '{report_content}'")
    else:
        feedback_parts.append("Report file missing")

    # 5. VLM Verification (20 pts)
    # Check if the chart was actually visible and if the report matches the chart
    frames = sample_trajectory_frames(traj, n=4)
    final_img = get_final_screenshot(traj)
    if final_img:
        frames.append(final_img)
        
    vlm_prompt = f"""
    The user is performing a Quality Control analysis in JASP.
    1. Look for a "Control Chart" or "X-bar Chart".
    2. Does the chart show data points?
    3. Are there any RED points (indicating Out of Control)?
    4. The user reported: "{report_content}". Does this match the chart? 
       (Red points = Out of Control, No red points = In Control)
    """
    
    vlm_result = query_vlm(frames, vlm_prompt)
    
    if vlm_result.get('success'):
        score += 20
        feedback_parts.append("Visual verification passed")
    else:
        feedback_parts.append("Visual verification failed")

    # Final tally
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }