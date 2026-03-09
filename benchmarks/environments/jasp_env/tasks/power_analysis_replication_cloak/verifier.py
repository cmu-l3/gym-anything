#!/usr/bin/env python3
import json
import os
import re
import zipfile
import tempfile
import base64
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_power_analysis_replication_cloak(traj, env_info, task_info):
    """
    Verifies the JASP Power Analysis task.
    
    Criteria:
    1. Report file exists and contains correct Cohen's d and Sample Size.
    2. JASP project file exists and is a valid ZIP.
    3. Files were created during the task (anti-gaming).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_d = metadata.get('target_cohens_d', 1.71)
    target_d_tol = metadata.get('target_cohens_d_tolerance', 0.1)
    target_n = metadata.get('target_sample_size', 18)
    target_n_tol = metadata.get('target_sample_size_tolerance', 4)

    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Verify JASP File (30 Points)
    jasp_exists = result_data.get('jasp_exists', False)
    jasp_fresh = result_data.get('jasp_created_during_task', False)
    
    if jasp_exists and jasp_fresh:
        score += 30
        feedback_parts.append("JASP project file saved successfully.")
        
        # Optional: Validate it's a real JASP file (ZIP format)
        # We need to copy the JASP file out to check its internals
        try:
            temp_jasp = tempfile.NamedTemporaryFile(delete=False, suffix='.jasp')
            copy_from_env(result_data['jasp_path'], temp_jasp.name)
            
            if zipfile.is_zipfile(temp_jasp.name):
                # We could inspect contents here (e.g., look for 'Analysis' in manifest)
                # For now, being a valid zip created by JASP is good evidence
                pass
            else:
                score -= 10
                feedback_parts.append("Warning: Saved file is not a valid JASP archive.")
            
            os.unlink(temp_jasp.name)
        except Exception:
            # If copy fails (e.g. large file), we still credit existence based on JSON
            pass
            
    elif jasp_exists:
        score += 10
        feedback_parts.append("JASP file exists but timestamp suggests it wasn't modified during task.")
    else:
        feedback_parts.append("JASP project file not found.")

    # 3. Verify Report Content (70 Points)
    report_exists = result_data.get('report_exists', False)
    
    if report_exists:
        try:
            content_b64 = result_data.get('report_content_base64', "")
            content = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
            
            # Extract numbers using regex
            # Look for floating point numbers for d, and integers for N
            floats = [float(x) for x in re.findall(r"[-+]?\d*\.\d+|\d+", content)]
            
            # Logic to identify which number is which
            # d is usually small (< 5.0), N is larger (> 10)
            found_d = False
            found_n = False
            
            val_d = 0.0
            val_n = 0
            
            for num in floats:
                # Check for Cohen's d match
                if not found_d and abs(num - target_d) <= target_d_tol:
                    val_d = num
                    found_d = True
                    continue
                
                # Check for Sample Size match
                # N must be integer-ish
                if not found_n and num > 10 and abs(num - target_n) <= target_n_tol:
                    val_n = int(num)
                    found_n = True
                    continue

            # Scoring based on extracted values
            if found_d:
                score += 35
                feedback_parts.append(f"Correct Effect Size reported (d={val_d}).")
            else:
                feedback_parts.append(f"Effect Size not found or incorrect (Expected ~{target_d}).")

            if found_n:
                score += 35
                feedback_parts.append(f"Correct Sample Size reported (N={val_n}).")
            else:
                feedback_parts.append(f"Sample Size not found or incorrect (Expected ~{target_n}).")
                
        except Exception as e:
            feedback_parts.append(f"Error parsing report: {str(e)}")
    else:
        feedback_parts.append("Report file not found.")

    # Final Result
    passed = score >= 80  # Requires JASP file + roughly correct values
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }