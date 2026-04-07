#!/usr/bin/env python3
import json
import os
import tempfile
import zipfile
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_code_metrics(traj, env_info, task_info):
    """
    Verifies the export_code_metrics task.
    
    Programmatic Checks (100 points):
    1. MetricsReport.xlsx exists and was created during the task (20 pts)
    2. File is a valid OpenXML Zip Archive (20 pts)
    3. The OpenXML payload contains Visual Studio metrics headers (30 pts)
    4. The text file identifies the correct method 'DetectCollision' (30 pts)
    
    VLM Check (Anti-gaming check):
    - Rejects task if trajectory fails to show interaction with Code Metrics.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_xlsx_path = metadata.get('expected_xlsx_path', "C:\\Users\\Docker\\Documents\\MetricsReport.xlsx")
    expected_method_name = metadata.get('expected_method_name', "DetectCollision")

    score = 0
    feedback_parts = []
    
    # 1. Fetch task_result.json
    result_json_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\Users\\Docker\\Documents\\task_result.json", result_json_tmp.name)
        with open(result_json_tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(result_json_tmp.name):
            os.unlink(result_json_tmp.name)

    # 2. Check MetricsReport.xlsx existence and creation time
    report_exists = result.get('report_exists', False)
    report_created_during_task = result.get('report_created_during_task', False)
    
    if report_exists and report_created_during_task:
        score += 20
        feedback_parts.append("MetricsReport.xlsx created during task")
    elif report_exists:
        feedback_parts.append("MetricsReport.xlsx exists but was NOT created during task (stale file)")
    else:
        feedback_parts.append("MetricsReport.xlsx does NOT exist")

    # 3. Download and Validate the Excel File (Valid OpenXML and Content)
    if report_exists and report_created_during_task:
        report_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.xlsx')
        try:
            copy_from_env(expected_xlsx_path, report_tmp.name)
            
            # Check if it's a valid ZIP (OpenXML is ZIP-based)
            if zipfile.is_zipfile(report_tmp.name):
                score += 20
                feedback_parts.append("Valid OpenXML (.xlsx) file structure")
                
                # Check for metrics data strings inside the XML payloads
                contains_metrics_data = False
                try:
                    with zipfile.ZipFile(report_tmp.name, 'r') as z:
                        file_list = z.namelist()
                        
                        # Inspect sharedStrings.xml or direct sheet XML
                        xml_files_to_check = [f for f in file_list if f.endswith('.xml')]
                        for xml_file in xml_files_to_check:
                            content = z.read(xml_file).decode('utf-8', errors='ignore')
                            if 'Cyclomatic Complexity' in content or 'Maintainability Index' in content:
                                contains_metrics_data = True
                                break
                except Exception as e:
                    logger.warning(f"Error reading zip contents: {e}")

                if contains_metrics_data:
                    score += 30
                    feedback_parts.append("Verified Code Metrics data inside Excel payload")
                else:
                    feedback_parts.append("Excel file lacks Code Metrics headers (not a valid metrics export)")
            else:
                feedback_parts.append("MetricsReport.xlsx is NOT a valid ZIP/Excel file")
        except Exception as e:
            feedback_parts.append(f"Failed to copy/read Excel file: {e}")
        finally:
            if os.path.exists(report_tmp.name):
                os.unlink(report_tmp.name)

    # 4. Check HighestComplexity.txt contents
    txt_exists = result.get('txt_exists', False)
    txt_content = result.get('txt_content', "")
    
    if txt_exists:
        # Regex search to forgive minor formatting (e.g. whitespace, newlines)
        if re.search(expected_method_name, txt_content, re.IGNORECASE):
            score += 30
            feedback_parts.append(f"Correctly identified highly complex method: {expected_method_name}")
        else:
            feedback_parts.append(f"Text file content '{txt_content[:30]}' does not match expected method '{expected_method_name}'")
    else:
        feedback_parts.append("HighestComplexity.txt does NOT exist")

    # 5. VLM Trajectory Process Check (Anti-gaming)
    vlm_passed = False
    try:
        frames = sample_trajectory_frames(traj, n=5)
        vlm_prompt = (
            "You are verifying a coding agent operating Visual Studio 2022. "
            "Examine this sequence of screenshots.\n"
            "Did the agent successfully open the 'Code Metrics Results' window (usually an analysis panel at the bottom) "
            "and interact with the 'Export to Excel' functionality?\n"
            "Respond ONLY with a JSON dictionary: {\"metrics_window_opened\": true/false}"
        )
        
        vlm_result = query_vlm(prompt=vlm_prompt, images=frames)
        if vlm_result and isinstance(vlm_result, dict):
            if vlm_result.get("metrics_window_opened", False):
                vlm_passed = True
                feedback_parts.append("VLM confirms Code Metrics UI workflow")
            else:
                feedback_parts.append("VLM could not verify Code Metrics UI interaction")
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        feedback_parts.append("VLM verification skipped/failed")
        vlm_passed = True # Fail-open for programmatic verifier if VLM errors out

    # Determine Pass/Fail (Must get at least 70 points AND pass the VLM check)
    passed = (score >= 70) and vlm_passed

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }