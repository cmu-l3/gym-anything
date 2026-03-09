#!/usr/bin/env python3
"""
Verifier for legacy_manual_formatting_cleanup task.
Checks if manual formatting has been replaced with proper Styles.
"""

import json
import os
import logging
import tempfile
import shutil
from typing import Dict, Any, List

# Import gym_anything utilities (simulated path)
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Fallback for local testing
    def sample_trajectory_frames(*args, **kwargs): return []
    def get_final_screenshot(*args, **kwargs): return None
    def query_vlm(*args, **kwargs): return {"success": False}

# Import local writer utils
from utils.writer_verification_utils import copy_and_parse_document

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_legacy_cleanup(traj, env_info, task_info):
    """
    Verify that the document was cleaned up by applying styles.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('output_path', '/home/ga/Documents/styled_install_guide.docx')
    mappings = metadata.get('mappings', [])

    # Load result JSON
    try:
        temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
        os.unlink(temp_json.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}

    # Basic checks
    if not result_data.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output file not found."}
    
    if not result_data.get('file_created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "Output file exists but was not created/modified during the task."}

    # Load Document
    success, doc, error, temp_dir = copy_and_parse_document(expected_output_path, copy_from_env, file_format='docx')
    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse output document: {error}"}

    score = 0
    feedback_parts = []
    
    # --- Check Paragraph Styles (Heading 1, Heading 2) ---
    h1_target = [m for m in mappings if m['target_style'] == 'Heading 1'][0]
    h2_target = [m for m in mappings if m['target_style'] == 'Heading 2'][0]
    
    h1_correct = 0
    h1_total = len(h1_target['key_phrases'])
    for phrase in h1_target['key_phrases']:
        found = False
        for para in doc.paragraphs:
            if phrase in para.text:
                found = True
                style_name = para.style.name if para.style else ""
                if "Heading 1" in style_name:
                    h1_correct += 1
                break
        if not found:
            feedback_parts.append(f"Missing text: '{phrase}'")

    if h1_correct == h1_total:
        score += 25
        feedback_parts.append("All main titles correctly styled as Heading 1.")
    elif h1_correct > 0:
        score += 10
        feedback_parts.append(f"Some main titles styled ({h1_correct}/{h1_total}).")
    else:
        feedback_parts.append("Main titles NOT styled as Heading 1.")

    h2_correct = 0
    h2_total = len(h2_target['key_phrases'])
    for phrase in h2_target['key_phrases']:
        found = False
        for para in doc.paragraphs:
            if phrase in para.text:
                found = True
                style_name = para.style.name if para.style else ""
                if "Heading 2" in style_name:
                    h2_correct += 1
                break
        if not found:
            feedback_parts.append(f"Missing text: '{phrase}'")

    if h2_correct == h2_total:
        score += 25
        feedback_parts.append("All subtitles correctly styled as Heading 2.")
    elif h2_correct > 0:
        score += 10
        feedback_parts.append(f"Some subtitles styled ({h2_correct}/{h2_total}).")
    else:
        feedback_parts.append("Subtitles NOT styled as Heading 2.")

    # --- Check Character Styles (Source Text, Strong Emphasis) ---
    # Since we can't easily map exact original runs to new runs (structure changes),
    # we look for known content that SHOULD be styled.
    
    # Check Code (Source Text)
    # Content to check: "sudo apt-get update", "initdb -D", "ufw allow"
    code_phrases = ["sudo apt-get", "initdb", "ufw allow"]
    code_matches = 0
    
    for para in doc.paragraphs:
        for run in para.runs:
            # Check if run style contains "Source" or "Code"
            style_name = ""
            if run.style:
                style_name = run.style.name
            
            # Allow for paragraph level style (e.g. "Preformatted Text") if user used that instead of char style
            para_style = para.style.name if para.style else ""
            
            if any(cp in run.text for cp in code_phrases):
                # Verify style
                if "Source" in style_name or "Code" in style_name or "Verbatim" in style_name or "Source" in para_style:
                    code_matches += 1
                    # Avoid double counting multiple phrases in one run (unlikely here)
                    break
    
    if code_matches >= 2: # At least 2 of the 3 distinctive code blocks found styled
        score += 20
        feedback_parts.append("Code snippets correctly styled.")
    else:
        feedback_parts.append("Code snippets NOT styled correctly (expected 'Source Text' or similar).")

    # Check Warnings (Strong Emphasis)
    # Content: "CRITICAL:", "WARNING:", "NOTE:"
    warning_phrases = ["CRITICAL", "WARNING", "NOTE"]
    warning_matches = 0
    
    for para in doc.paragraphs:
        for run in para.runs:
            style_name = run.style.name if run.style else ""
            if any(wp in run.text for wp in warning_phrases):
                if "Strong" in style_name or "Emphasis" in style_name:
                    warning_matches += 1
                    break
    
    if warning_matches >= 2:
        score += 20
        feedback_parts.append("Warnings correctly styled.")
    else:
        feedback_parts.append("Warnings NOT styled correctly (expected 'Strong Emphasis').")

    # --- File Creation Bonus ---
    score += 10 # For creating the file
    
    # --- VLM Verification (Trajectory) ---
    # Check if the Styles panel was ever open or used
    frames = sample_trajectory_frames(traj, n=5)
    final_img = get_final_screenshot(traj)
    images = frames + ([final_img] if final_img else [])
    
    vlm_score = 0
    if images:
        prompt = "Did the user engage with the Styles panel or formatting menus in LibreOffice Writer? Do you see 'Heading 1' or 'Source Text' being applied?"
        vlm_res = query_vlm(images=images, prompt=prompt)
        if vlm_res.get("success") and vlm_res.get("parsed", {}).get("answer", False): # Assuming VLM returns answer boolean or similar structure
             # Note: simple VLM wrapper usually returns text.
             # We assume here we just want to verify visually if ambiguous.
             # For now, relying on programmatic check is safer, but we can verify final screenshot looks correct.
             pass

    # Cleanup
    shutil.rmtree(temp_dir, ignore_errors=True)

    passed = score >= 75
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }