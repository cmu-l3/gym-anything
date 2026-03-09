#!/usr/bin/env python3
"""
Verifier for create_sipoc_diagram task.

Verification Strategy:
1. File Existence: Checks for .eddx and .png files.
2. Timestamp Check: Ensures files were created during the task.
3. Content Analysis: Unzips the .eddx file (XML format) and checks for required text strings.
4. Visual Check: Basic file size validation and format check.
"""

import json
import os
import zipfile
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_sipoc_diagram(traj, env_info, task_info):
    """
    Verify that the SIPOC diagram was created correctly.
    """
    # 1. Setup and Load Results
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load the JSON result exported by the shell script
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Score Calculation Initialization
    score = 0
    feedback_parts = []
    
    eddx_info = result_data.get('eddx_file', {})
    png_info = result_data.get('png_file', {})
    
    # 3. Verify .eddx File (Source)
    eddx_valid = False
    if eddx_info.get('exists'):
        if eddx_info.get('created_during_task'):
            if eddx_info.get('size', 0) > 2000: # Empty/corrupt check
                score += 20
                eddx_valid = True
                feedback_parts.append("Valid .eddx file created.")
            else:
                feedback_parts.append(".eddx file too small.")
        else:
            feedback_parts.append(".eddx file not modified during task.")
    else:
        feedback_parts.append(".eddx file not found.")

    # 4. Verify .png File (Export)
    if png_info.get('exists'):
        if png_info.get('created_during_task'):
            if png_info.get('size', 0) > 5000: # Basic image size check
                score += 20
                feedback_parts.append("Valid .png export created.")
            else:
                feedback_parts.append(".png file too small.")
        else:
            feedback_parts.append(".png file not modified during task.")
    else:
        feedback_parts.append(".png export not found.")

    # 5. Content Verification (Deep Check of .eddx)
    # EdrawMax .eddx files are ZIP archives containing XML data (usually in 'pages' folder or root)
    content_score = 0
    required_strings = task_info.get('metadata', {}).get('required_strings', [])
    
    if eddx_valid:
        temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx')
        try:
            # Copy the actual .eddx file from the container
            copy_from_env(task_info['metadata']['eddx_path'], temp_eddx.name)
            
            # Extract text content from the archive
            text_content = ""
            with zipfile.ZipFile(temp_eddx.name, 'r') as zf:
                for filename in zf.namelist():
                    if filename.endswith(".xml") or filename.endswith(".json"):
                        try:
                            # Read and decode, ignoring errors
                            text_content += zf.read(filename).decode('utf-8', errors='ignore')
                        except:
                            pass
            
            # Check for required strings in the content
            found_strings = []
            for s in required_strings:
                if s in text_content:
                    found_strings.append(s)
            
            # Calculate content score
            # Total strings: ~6. 60 points allocated for content.
            # 10 points per string found.
            points_per_string = 10
            content_points = len(found_strings) * points_per_string
            score += content_points
            
            if len(found_strings) == len(required_strings):
                feedback_parts.append(f"All required text found in diagram ({len(found_strings)}/{len(required_strings)}).")
            else:
                feedback_parts.append(f"Found {len(found_strings)}/{len(required_strings)} required terms. Missing: {list(set(required_strings) - set(found_strings))}")

        except zipfile.BadZipFile:
            feedback_parts.append("Error: .eddx file is not a valid zip archive.")
        except Exception as e:
            feedback_parts.append(f"Error checking .eddx content: {str(e)}")
        finally:
            if os.path.exists(temp_eddx.name):
                os.unlink(temp_eddx.name)
    
    # 6. Final Evaluation
    # Total possible: 20 (eddx) + 20 (png) + 60 (content) = 100
    # Pass threshold: 70
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }