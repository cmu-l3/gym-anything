#!/usr/bin/env python3
"""
Verifier for Bain Informative Hypothesis Task in JASP.

Verification Logic:
1. Check if the JASP project file (.jasp) exists and is a valid ZIP.
2. Inspect internal JSONs in the .jasp archive to verify:
   - The Bain module was used (analysis type "BainAnova" or similar).
   - The correct variables were assigned (libido, dose).
   - The hypothesis constraints were defined (containing "1<2<3" logic).
3. Check the text output file for the correct posterior probability.
4. Verify anti-gaming (files created during task time).
"""

import json
import os
import zipfile
import tempfile
import logging
import re
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bain_hypothesis(traj, env_info, task_info):
    """
    Verify the agent correctly configured the Bain analysis and reported results.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load Metadata
    metadata = task_info.get('metadata', {})
    ground_truth_prob = metadata.get('ground_truth_probability', 0.92)
    prob_tolerance = metadata.get('probability_tolerance', 0.05)
    constraint_signatures = metadata.get('constraint_signature', ["1<2<3", "dose1<dose2<dose3"])

    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Verify JASP File Existence and Freshness (20 pts)
    jasp_exists = result_data.get("jasp_file_exists", False)
    jasp_fresh = result_data.get("jasp_created_during_task", False)
    
    if jasp_exists:
        if jasp_fresh:
            score += 20
            feedback_parts.append("JASP file created.")
        else:
            score += 5
            feedback_parts.append("JASP file exists but timestamp is old.")
    else:
        feedback_parts.append("JASP file not found.")
        # Fail early if no file
        return {"passed": False, "score": 0, "feedback": "JASP project file not found."}

    # 3. Analyze JASP File Content (40 pts)
    # The .jasp file is a zip. We need to extract it and find the analysis definition.
    temp_jasp = tempfile.NamedTemporaryFile(delete=False, suffix='.zip')
    analysis_verified = False
    constraints_verified = False
    
    try:
        copy_from_env("/tmp/Viagra_Bain.jasp", temp_jasp.name)
        
        with zipfile.ZipFile(temp_jasp.name, 'r') as z:
            # JASP structure usually has nested folders like 'analysis-1', 'data', etc.
            # We look for JSON files that describe analyses.
            # Filenames might be 'analysis.json' inside numbered folders.
            
            for filename in z.namelist():
                if filename.endswith(".json"):
                    try:
                        with z.open(filename) as f:
                            content = json.load(f)
                            # Convert to string for easy searching
                            content_str = json.dumps(content)
                            
                            # Check for Bain Module usage
                            if "Bain" in content_str or "bain" in content_str:
                                # Look for specific Bain Anova identifier
                                if "BainAnova" in content_str or "bainAnova" in content_str:
                                    analysis_verified = True
                            
                            # Check for Constraints
                            # The constraints are usually stored in a string field
                            # e.g. "model": "1<2<3" or similar
                            for sig in constraint_signatures:
                                # Remove spaces for robust matching
                                clean_content = content_str.replace(" ", "")
                                clean_sig = sig.replace(" ", "")
                                if clean_sig in clean_content:
                                    constraints_verified = True
                                    break
                    except Exception:
                        continue
                        
    except Exception as e:
        feedback_parts.append(f"Failed to inspect JASP file content: {e}")
    finally:
        if os.path.exists(temp_jasp.name):
            os.unlink(temp_jasp.name)

    if analysis_verified:
        score += 20
        feedback_parts.append("Bain ANOVA analysis found.")
    else:
        feedback_parts.append("No Bain ANOVA analysis found in project.")

    if constraints_verified:
        score += 20
        feedback_parts.append("Hypothesis constraints (1<2<3) found.")
    else:
        feedback_parts.append("Informative hypothesis constraints not found.")

    # 4. Verify Text Result (40 pts)
    text_exists = result_data.get("text_file_exists", False)
    text_content = result_data.get("text_content", "")
    
    if text_exists:
        score += 10
        feedback_parts.append("Result text file exists.")
        
        # Extract number from text
        # Look for float-like patterns
        floats = re.findall(r"0\.\d+|1\.0", text_content)
        if floats:
            # Take the largest number found (usually the posterior prob)
            # or the one closest to expected
            reported_val = float(floats[0])
            
            diff = abs(reported_val - ground_truth_prob)
            if diff <= prob_tolerance:
                score += 30
                feedback_parts.append(f"Reported probability ({reported_val}) is correct.")
            else:
                feedback_parts.append(f"Reported probability ({reported_val}) incorrect. Expected ~{ground_truth_prob}.")
        else:
            feedback_parts.append("No valid number found in text file.")
    else:
        feedback_parts.append("Result text file missing.")

    # Final Evaluation
    passed = (score >= 70) and analysis_verified
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }