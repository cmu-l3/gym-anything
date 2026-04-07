#!/usr/bin/env python3
"""
Verifier for Firefox Hostile CSS Print Cleanup Task.

VERIFICATION METRICS:
1. Anti-gaming: PDF was created during the task timeframe.
2. File existence: Target PDF exists.
3. Content Preservation: PDF contains expected text.
4. CSS Defeated: PDF does not contain the hostile print warning.
5. DOM Overlays Removed: PDF does not contain overlay text.
6. VLM Check: Developer tools opened during trajectory.
"""

import json
import os
import tempfile
import logging
import re

from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_pdf_cleanup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_pdf = metadata.get('output_pdf', '/home/ga/Documents/Research/Clean_Apollo_Report.pdf')
    required_strings = metadata.get('required_strings', [])
    forbidden_strings = metadata.get('forbidden_strings', [])

    score = 0
    feedback_parts = []

    # 1. Read JSON result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    output_exists = result.get('output_exists', False)
    created_during_task = result.get('file_created_during_task', False)

    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Output PDF not found."}
    
    score += 10
    feedback_parts.append("PDF exists")

    if not created_during_task:
        feedback_parts.append("Warning: PDF was not created during task (timestamp mismatch)")
    else:
        score += 10
        feedback_parts.append("PDF created during task")

    # 2. Analyze the PDF File Content
    temp_pdf = tempfile.NamedTemporaryFile(delete=False, suffix='.pdf')
    pdf_text = ""
    is_firefox_pdf = False
    
    try:
        copy_from_env(expected_pdf, temp_pdf.name)
        
        # Check metadata to prevent script-based generation bypass (Anti-gaming)
        with open(temp_pdf.name, 'rb') as f:
            raw_pdf = f.read()
            if b"Mozilla" in raw_pdf or b"Firefox" in raw_pdf or b"cairo" in raw_pdf:
                is_firefox_pdf = True
        
        if is_firefox_pdf:
            score += 10
            feedback_parts.append("PDF metadata confirms Firefox generator")
        else:
            feedback_parts.append("Warning: PDF metadata does NOT match Firefox (possible bypass)")

        # Extract text using pdfminer
        try:
            from pdfminer.high_level import extract_text
            pdf_text = extract_text(temp_pdf.name)
        except ImportError:
            # Fallback if pdfminer is missing
            logger.warning("pdfminer not found, trying basic string extraction")
            pdf_text = re.sub(r'[^a-zA-Z0-9 \n]', '', raw_pdf.decode('ascii', errors='ignore'))
            
    except Exception as e:
        logger.error(f"Error reading PDF: {e}")
    finally:
        if os.path.exists(temp_pdf.name):
            os.unlink(temp_pdf.name)

    # Normalize whitespace for robust matching
    normalized_text = " ".join(pdf_text.split())

    # 3. Check Required Strings (Content Preserved)
    content_preserved = True
    for req in required_strings:
        if req not in normalized_text:
            content_preserved = False
            feedback_parts.append(f"Missing required text: '{req}'")
            break
            
    if content_preserved:
        score += 30
        feedback_parts.append("Article content preserved")

    # 4. Check Forbidden Strings (Hostile CSS & Overlays Defeated)
    css_defeated = True
    overlays_removed = True
    
    for string in forbidden_strings:
        if string in normalized_text:
            if string == "PRINTING IS DISABLED":
                css_defeated = False
                feedback_parts.append("Hostile print CSS was not disabled")
            else:
                overlays_removed = False
                feedback_parts.append(f"DOM overlay text still present: '{string}'")
                
    if css_defeated:
        score += 20
        feedback_parts.append("Hostile print CSS successfully disabled")
        
    if overlays_removed:
        score += 20
        feedback_parts.append("DOM overlays successfully removed")

    # 5. VLM Trajectory Verification
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = "Look at these screenshots from a web browsing session. Did the user open the Browser Developer Tools (Inspector, Style Editor, or Console) to modify the page at any point?"
            vlm_result = query_vlm(images=frames, prompt=prompt)
            if vlm_result and "yes" in str(vlm_result).lower():
                vlm_score = 10
                feedback_parts.append("VLM confirms DevTools usage")
            else:
                feedback_parts.append("VLM did not detect DevTools usage")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")

    # Maximum base score = 100
    final_score = min(100, score)
    
    # Success Criteria Check
    # To pass, the agent must have created the file, preserved the content, AND disabled the print CSS.
    passed = (output_exists and 
              created_during_task and 
              content_preserved and 
              css_defeated and 
              final_score >= 70)

    return {
        "passed": passed,
        "score": final_score,
        "feedback": " | ".join(feedback_parts)
    }