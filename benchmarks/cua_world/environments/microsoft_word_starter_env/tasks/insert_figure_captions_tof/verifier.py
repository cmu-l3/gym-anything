#!/usr/bin/env python3
"""
Verifier for insert_figure_captions_tof task.

Verifies:
1. Document saved and modified during task.
2. Presence of SEQ Figure fields (Word's native captioning).
3. Presence of Table of Figures (TOC field).
4. Correct caption text for all 4 images.
5. VLM verification of visual layout.
"""

import json
import logging
import os
import re
import tempfile
import zipfile
import shutil
from vlm_utils import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_insert_figure_captions_tof(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get("metadata", {})
    expected_captions = metadata.get("captions", [])
    
    # 1. Retrieve Result JSON
    temp_dir = tempfile.mkdtemp()
    result_path = os.path.join(temp_dir, "task_result.json")
    docx_local_path = os.path.join(temp_dir, "BrownfieldReport.docx")
    
    try:
        copy_from_env("C:\\tmp\\task_result.json", result_path)
        with open(result_path, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}

    # 2. Check File Existence & Timestamp (Gatekeeper)
    if not result_data.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Document not found at expected path."}
    
    if not result_data.get("file_created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "Document was not modified during the task session."}

    # 3. Retrieve DOCX for Analysis
    try:
        copy_from_env(result_data.get("doc_path", ""), docx_local_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve document: {e}"}

    score = 0
    feedback_parts = []
    
    # --- Programmatic Verification (XML Parsing) ---
    try:
        with zipfile.ZipFile(docx_local_path, 'r') as zf:
            document_xml = zf.read('word/document.xml').decode('utf-8')
            
            # A. Check for SEQ fields (Captions) - 40 pts
            # Pattern matches <w:instrText>SEQ Figure</w:instrText> or similar
            seq_count = len(re.findall(r'SEQ\s+Figure', document_xml, re.IGNORECASE))
            
            if seq_count >= 4:
                score += 40
                feedback_parts.append(f"Found {seq_count} properly formatted Figure captions.")
            elif seq_count > 0:
                score += seq_count * 10
                feedback_parts.append(f"Found partial Figure captions ({seq_count}/4).")
            else:
                feedback_parts.append("No proper Word captions found (Insert > Caption not used).")

            # B. Check for TOC field (Table of Figures) - 20 pts
            # Pattern matches TOC \c "Figure"
            tof_match = re.search(r'TOC\s+.*\\c\s+"?Figure"?', document_xml, re.IGNORECASE)
            if tof_match:
                score += 20
                feedback_parts.append("Table of Figures field code found.")
            else:
                feedback_parts.append("Table of Figures not found or incorrect format.")

            # C. Check Caption Text Content - 20 pts
            # Simple check if the text exists in the XML
            text_score = 0
            for cap in expected_captions:
                # We normalize simple spaces/dashes for robustness
                clean_cap = re.escape(cap)
                if re.search(clean_cap, document_xml, re.IGNORECASE):
                    text_score += 5
            
            score += text_score
            if text_score == 20:
                feedback_parts.append("All caption texts matched.")
            else:
                feedback_parts.append(f"Caption text match score: {text_score}/20.")

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error parsing DOCX XML: {e}"}

    # --- VLM Verification (Visual Check) ---
    # 20 pts
    
    frames = sample_trajectory_frames(traj, n=3)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    Review the final screenshot of a Microsoft Word document.
    Does it show:
    1. A Table of Figures (list of figures with page numbers)?
    2. Any visible image with a caption starting with "Figure X:"?
    
    Score 20 points if both are visible. Score 10 if only one is visible. Score 0 otherwise.
    Return JSON: {"score": int, "reason": "string"}
    """
    
    try:
        vlm_res = query_vlm(prompt=vlm_prompt, images=[final_screen])
        if vlm_res and 'parsed' in vlm_res:
            vlm_score = vlm_res['parsed'].get('score', 0)
            score += vlm_score
            feedback_parts.append(f"Visual verification: {vlm_res['parsed'].get('reason', '')}")
        else:
            # Fallback if VLM fails: check if ToF field was found programmatically to give partial credit
            if tof_match:
                score += 10
                feedback_parts.append("VLM skipped, fallback credit applied.")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")

    # Final tally
    passed = score >= 60 and seq_count >= 2 and (tof_match is not None)
    
    # Cleanup
    shutil.rmtree(temp_dir, ignore_errors=True)
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback_parts)
    }