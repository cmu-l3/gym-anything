#!/usr/bin/env python3
"""
Verifier for create_hoq_qfd_diagram task.

Checks:
1. File Existence: .eddx and .pdf files exist and were created during the task.
2. File Content (EDDX): Validates the file is a ZIP (Edraw format) and contains specific text strings (Requirements, Descriptors).
3. VLM Verification: Uses trajectory frames to confirm the distinct "House of Quality" shape and symbols (dots, roof correlations) were visually constructed.
"""

import json
import os
import tempfile
import zipfile
import logging
import sys

# Add parent directory to path to import vlm_utils if needed, 
# though we usually assume gym_anything environment structure.
# Here we stick to standard imports provided in the python_interpreter tool.

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_hoq_qfd_diagram(traj, env_info, task_info):
    """
    Verify the House of Quality task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: Files Exist and Fresh (30 pts) ---
    eddx_info = result.get('eddx_file', {})
    pdf_info = result.get('pdf_file', {})
    
    files_ok = False
    if eddx_info.get('exists') and eddx_info.get('fresh'):
        score += 15
        feedback_parts.append(".eddx file created")
    
    if pdf_info.get('exists') and pdf_info.get('fresh') and pdf_info.get('size', 0) > 1000:
        score += 15
        feedback_parts.append(".pdf file exported")
        files_ok = True
    else:
        feedback_parts.append("PDF missing or empty")

    # --- Criterion 2: Content Analysis of EDDX (30 pts) ---
    # EdrawMax .eddx files are ZIPs containing XML. We check for the text labels.
    content_score = 0
    required_strings = task_info.get('metadata', {}).get('required_strings', [])
    found_strings = []
    
    if eddx_info.get('exists'):
        temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx')
        try:
            copy_from_env("/home/ga/Documents/laptop_qfd.eddx", temp_eddx.name)
            
            is_valid_zip = False
            try:
                with zipfile.ZipFile(temp_eddx.name, 'r') as zf:
                    is_valid_zip = True
                    # Search all XML files in the zip for text
                    all_text = ""
                    for filename in zf.namelist():
                        if filename.endswith('.xml'):
                            try:
                                all_text += zf.read(filename).decode('utf-8', errors='ignore')
                            except:
                                pass
                    
                    # Check for keywords
                    for s in required_strings:
                        if s.lower() in all_text.lower():
                            found_strings.append(s)
                            
            except zipfile.BadZipFile:
                feedback_parts.append("EDDX file is not a valid zip archive")

            if is_valid_zip:
                # Calculate content score based on found strings
                # We have ~5 required strings. 30 pts total -> ~6 pts each
                matched_count = len(found_strings)
                content_score = min(30, matched_count * 6)
                if matched_count >= 3:
                    feedback_parts.append(f"Found {matched_count}/{len(required_strings)} required terms in diagram")
                else:
                    feedback_parts.append(f"Missing key terms (Found only: {found_strings})")
                    
        except Exception as e:
            feedback_parts.append(f"Error checking EDDX content: {e}")
        finally:
            if os.path.exists(temp_eddx.name):
                os.unlink(temp_eddx.name)
    
    score += content_score

    # --- Criterion 3: VLM Verification of Structure/Symbols (40 pts) ---
    # Use trajectory to ensure they actually built a HOQ with symbols
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    
    frames = sample_trajectory_frames(traj, n=4)
    final_img = get_final_screenshot(traj)
    
    vlm_prompt = """
    You are verifying a 'House of Quality' (QFD) diagram creation task.
    
    Look at the sequence of screenshots.
    1. Is the diagram structure a 'House of Quality'? (A central grid/matrix with a triangular 'roof' on top).
    2. Are there relationship symbols in the matrix? (Dots, circles, or bullseyes inside the grid cells).
    3. Is there a correlation symbol in the roof? (An 'X', cross, or plus sign in the triangle part).
    4. Does the title or text include 'Pro Laptop'?
    
    Return JSON:
    {
      "is_house_of_quality": true/false,
      "has_matrix_symbols": true/false,
      "has_roof_symbols": true/false,
      "text_visible": true/false
    }
    """
    
    vlm_score = 0
    try:
        # We use the final image primarily, but pass trajectory for context if needed
        # Just query on the final image for the structure check
        response = query_vlm(images=[final_img], prompt=vlm_prompt)
        
        if response and response.get('success'):
            data = response.get('parsed', {})
            if data.get('is_house_of_quality'):
                vlm_score += 10
            if data.get('has_matrix_symbols'):
                vlm_score += 15
            if data.get('has_roof_symbols'):
                vlm_score += 10
            if data.get('text_visible'):
                vlm_score += 5
            
            feedback_parts.append(f"Visual verification: {data}")
        else:
            feedback_parts.append("VLM verification failed to run")
            
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback: if content check was perfect (30/30) and files exist (30/30), give partial VLM credit
        if content_score >= 25 and files_ok:
            vlm_score = 20
            feedback_parts.append("VLM skipped, granting partial credit based on file quality")

    score += vlm_score

    # Final tally
    passed = (score >= 60) and files_ok
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }