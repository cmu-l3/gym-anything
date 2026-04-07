#!/usr/bin/env python3
"""
Verifier for bundle_download_documents task.
Checks if the agent successfully downloaded a ZIP containing the specific documents.
"""

import json
import os
import zipfile
import tempfile
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bundle_download_documents(traj, env_info, task_info):
    """
    Verify the agent created a ZIP with specific PDFs.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', '/home/ga/Downloads/vendor_package.zip')
    
    # 1. Retrieve task result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Check basic file existence from JSON
    if not result.get("output_exists", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "The file 'vendor_package.zip' was not found in ~/Downloads."
        }

    # 2. Retrieve the ZIP file
    temp_zip = tempfile.NamedTemporaryFile(delete=False, suffix='.zip')
    try:
        copy_from_env(expected_output_path, temp_zip.name)
        
        # 3. Analyze ZIP content
        score = 0
        feedback = []
        
        if not zipfile.is_zipfile(temp_zip.name):
            return {"passed": False, "score": 10, "feedback": "File exists but is not a valid ZIP archive."}
        
        score += 20 # Valid ZIP
        
        with zipfile.ZipFile(temp_zip.name, 'r') as zf:
            file_list = zf.namelist()
            file_list_lower = [f.lower() for f in file_list]
            
            # Check for Annual Report
            has_annual_report = any("annual" in f and "report" in f and ".pdf" in f for f in file_list_lower)
            if has_annual_report:
                score += 35
                feedback.append("Found 'Annual Report' in archive.")
            else:
                feedback.append("Missing 'Annual Report' in archive.")

            # Check for Contract Template
            has_contract = any("contract" in f and "template" in f and ".pdf" in f for f in file_list_lower)
            if has_contract:
                score += 35
                feedback.append("Found 'Contract Template' in archive.")
            else:
                feedback.append("Missing 'Contract Template' in archive.")

        # 4. Check timestamp (anti-gaming)
        if result.get("file_created_during_task", False):
            score += 10
            feedback.append("File created during task session.")
        else:
            feedback.append("Warning: File timestamp indicates it was not created during this task.")

        # Final pass determination
        passed = (has_annual_report and has_contract and score >= 90)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " ".join(feedback)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error analyzing output file: {e}"}
    finally:
        if os.path.exists(temp_zip.name):
            os.unlink(temp_zip.name)