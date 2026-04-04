#!/usr/bin/env python3
import json
import os
import zipfile
import tempfile
import re
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("verifier")

def verify_ttest_effect_size(traj, env_info, task_info):
    """
    Verifies that the agent performed an Independent Samples T-Test,
    enabled Cohen's d with 95% CI, and reported the correct values.
    """
    # 1. Setup and Load Result
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Load the export result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # Metadata for verification
    meta = task_info.get("metadata", {})
    ground_truth = meta.get("ground_truth", {})
    gt_lower = ground_truth.get("ci_lower", -0.017)
    gt_upper = ground_truth.get("ci_upper", 1.004)
    tolerance = ground_truth.get("tolerance", 0.05)

    # 2. Check OMV File Existence and Configuration (50 points)
    if result_data.get("omv_exists") and result_data.get("omv_created_during_task"):
        score += 10
        feedback.append("OMV file created.")
        
        # Download OMV file to verify internal structure
        temp_omv = tempfile.NamedTemporaryFile(delete=False, suffix='.omv')
        omv_path_remote = meta.get("expected_omv_path", "/home/ga/Documents/Jamovi/ToothGrowth_EffectSize.omv")
        
        try:
            copy_from_env(omv_path_remote, temp_omv.name)
            
            # OMV is a ZIP file. We look for the analysis definition.
            # Usually found in the zip as 'index.html' (results) or analysis binaries.
            # But Jamovi also stores analysis state in 'metadata.json' or specific analysis JSONs.
            # We look for a file inside the zip that contains "ttestIS" (Independent Samples).
            
            is_ttest_found = False
            is_effect_size_found = False
            is_ci_found = False
            
            if zipfile.is_zipfile(temp_omv.name):
                with zipfile.ZipFile(temp_omv.name, 'r') as z:
                    # Search through files for analysis config
                    # Jamovi file structure typically has 'meta' or 'analysis' objects in JSON format
                    for filename in z.namelist():
                        if filename.endswith('.json') or filename.endswith('00'): # 00 are sometimes analysis states
                            try:
                                content = z.read(filename).decode('utf-8', errors='ignore')
                                if 'ttestIS' in content:
                                    is_ttest_found = True
                                    # Check for specific options in the JSON content
                                    # Regex is safer as JSON structure varies by version
                                    # Looking for "effectSize": true
                                    if '"effectSize":true' in content.replace(" ", ""):
                                        is_effect_size_found = True
                                    # Looking for "ci": true (associated with effect size or mean diff)
                                    # Note: 'ci' option key is common for T-Test options
                                    if '"ci":true' in content.replace(" ", ""):
                                        is_ci_found = True
                            except:
                                continue
            
            if is_ttest_found:
                score += 20
                feedback.append("T-Test analysis found in OMV.")
                if is_effect_size_found:
                    score += 10
                    feedback.append("Effect Size option enabled.")
                else:
                    feedback.append("Effect Size option NOT found in OMV.")
                
                if is_ci_found:
                    score += 10
                    feedback.append("Confidence Interval option enabled.")
                else:
                    feedback.append("Confidence Interval option NOT found in OMV.")
            else:
                feedback.append("No Independent Samples T-Test found in OMV file.")
                
        except Exception as e:
            feedback.append(f"Failed to inspect OMV file: {str(e)}")
        finally:
            if os.path.exists(temp_omv.name):
                os.unlink(temp_omv.name)
    else:
        feedback.append("OMV file missing or not created during task.")

    # 3. Check Report Content (50 points)
    if result_data.get("report_exists") and result_data.get("report_created_during_task"):
        content = result_data.get("report_content", "")
        
        # Look for numbers in the text
        # Pattern: look for floating point numbers
        numbers = re.findall(r"[-+]?\d*\.\d+|\d+", content)
        floats = []
        for n in numbers:
            try:
                floats.append(float(n))
            except:
                pass
        
        # We expect two numbers close to the ground truth
        found_lower = False
        found_upper = False
        
        # Simple check: are there numbers within tolerance of Lower and Upper?
        # Lower: ~ -0.017
        # Upper: ~ 1.004
        
        for val in floats:
            if abs(val - gt_lower) < tolerance:
                found_lower = True
            if abs(val - gt_upper) < tolerance:
                found_upper = True
                
        if found_lower:
            score += 25
            feedback.append(f"Reported Lower Bound is correct (found ~{gt_lower:.3f}).")
        else:
            feedback.append(f"Reported Lower Bound incorrect or missing (Expected ~{gt_lower:.3f}).")
            
        if found_upper:
            score += 25
            feedback.append(f"Reported Upper Bound is correct (found ~{gt_upper:.3f}).")
        else:
            feedback.append(f"Reported Upper Bound incorrect or missing (Expected ~{gt_upper:.3f}).")
            
    else:
        feedback.append("Report file missing or not created during task.")

    # 4. Final Verdict
    # Threshold: Must have OMV with T-Test (30pts) AND at least one correct value (25pts) = 55 minimum
    # But let's set a stricter threshold for 'passing'
    passed = score >= 80  # Requires OMV correct + both values correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }