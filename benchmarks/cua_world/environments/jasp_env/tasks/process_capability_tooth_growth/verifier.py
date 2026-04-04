#!/usr/bin/env python3
import json
import os
import zipfile
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_process_capability(traj, env_info, task_info):
    """
    Verify Process Capability Analysis task.
    
    Criteria:
    1. JASP file created during task.
    2. Report file created with correct Cpk value.
    3. JASP file internal inspection confirms correct parameters (LSL=5, USL=35).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_cpk = metadata.get('expected_cpk', 0.584)
    cpk_tolerance = metadata.get('cpk_tolerance', 0.05)
    
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

    # 2. Check JASP File Existence & Freshness
    if result_data.get('jasp_exists') and result_data.get('jasp_created_during_task'):
        score += 20
        feedback_parts.append("JASP file created.")
    elif result_data.get('jasp_exists'):
        score += 10
        feedback_parts.append("JASP file exists but timestamp is old.")
    else:
        feedback_parts.append("JASP file not found.")

    # 3. Check Report Content (Cpk)
    report_valid = False
    if result_data.get('report_exists'):
        content = result_data.get('report_content', '').strip()
        try:
            # Extract float from string (handle cases like "Cpk = 0.58" or just "0.58")
            match = re.search(r"[-+]?\d*\.\d+|\d+", content)
            if match:
                val = float(match.group())
                if abs(val - expected_cpk) <= cpk_tolerance:
                    score += 40
                    report_valid = True
                    feedback_parts.append(f"Reported Cpk ({val}) is correct.")
                else:
                    feedback_parts.append(f"Reported Cpk ({val}) is incorrect (expected ~{expected_cpk}).")
            else:
                feedback_parts.append("Could not parse number from report.")
        except Exception:
            feedback_parts.append("Error parsing report content.")
    else:
        feedback_parts.append("Report file not found.")

    # 4. Deep Inspection of JASP File (Configuration)
    # JASP files are ZIPs. We look for the analysis configuration.
    # Since parsing internal JSON might be fragile across versions, we check if 
    # the ZIP contains specific strings related to the config (LSL=5, USL=35).
    config_score = 0
    if result_data.get('jasp_exists'):
        temp_jasp = tempfile.NamedTemporaryFile(delete=False, suffix='.jasp')
        try:
            copy_from_env("/tmp/analysis_artifact.jasp", temp_jasp.name)
            
            if zipfile.is_zipfile(temp_jasp.name):
                with zipfile.ZipFile(temp_jasp.name, 'r') as z:
                    # Search through files in the zip for configuration strings
                    found_proc_cap = False
                    found_lsl = False
                    found_usl = False
                    found_var = False
                    
                    for filename in z.namelist():
                        # We are looking for JSONs or analysis scripts
                        if filename.endswith('.json') or filename.endswith('.qml') or 'analysis' in filename:
                            try:
                                content = z.read(filename).decode('utf-8', errors='ignore')
                                # Loose string matching is more robust than strict path parsing here
                                if 'processCapability' in content or 'ProcessCapability' in content:
                                    found_proc_cap = True
                                if '"len"' in content or "'len'" in content:
                                    found_var = True
                                # Look for limit values associated with keys or just presence if context allows
                                if '5' in content and ('lower' in content.lower() or 'lsl' in content.lower()):
                                    found_lsl = True # Heuristic
                                if '35' in content and ('upper' in content.lower() or 'usl' in content.lower()):
                                    found_usl = True # Heuristic
                                
                                # Strict check: often keys are "lowerSpecificationLimit": 5
                                if '"lowerSpecificationLimit":5' in content.replace(" ", ""): 
                                    found_lsl = True
                                if '"upperSpecificationLimit":35' in content.replace(" ", ""):
                                    found_usl = True
                            except:
                                continue
                    
                    if found_proc_cap: config_score += 10
                    if found_var: config_score += 10
                    if found_lsl: config_score += 10
                    if found_usl: config_score += 10
            else:
                feedback_parts.append("JASP file is not a valid ZIP archive.")
        except Exception as e:
            feedback_parts.append(f"Failed to inspect JASP file: {str(e)}")
        finally:
            if os.path.exists(temp_jasp.name):
                os.unlink(temp_jasp.name)
    
    score += config_score
    if config_score == 40:
        feedback_parts.append("JASP configuration verified (Analysis, Var, Limits).")
    elif config_score > 0:
        feedback_parts.append(f"Partial JASP configuration verified ({config_score}/40 pts).")

    # Anti-gaming check: File creation + Config verification required
    passed = (score >= 70) and result_data.get('jasp_created_during_task')

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }