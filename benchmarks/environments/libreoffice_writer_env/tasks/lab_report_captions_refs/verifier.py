#!/usr/bin/env python3
"""
Verifier for lab_report_captions_refs task.
Checks for correct captions, dynamic cross-reference fields, and table of figures.
"""

import json
import logging
import os
import shutil
import tempfile
import zipfile
import re
from lxml import etree

# Add utils path if needed, though we'll implement specific XML checks here
import sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vlm_utils import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_lab_report_captions(traj, env_info, task_info):
    """
    Verify the Lab Report task.
    
    Criteria:
    1. File exists and is valid DOCX.
    2. Placeholders ([REF_FIG_...]) are REMOVED from text.
    3. Captions exist (Figures 1, 2, 3 with correct text).
    4. Cross-references are real fields (w:fldChar), not typed text.
    5. Table of Figures exists (TOC field with \c switch).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_output = metadata.get('output_path', '/home/ga/Documents/soil_report_final.docx')
    placeholders = metadata.get('placeholders', {}).values()
    expected_captions = metadata.get('captions', {})

    # 1. Get Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name) as f:
            res_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name): os.unlink(temp_json.name)

    if not res_data.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Output file not found"}

    # 2. Get DOCX File
    temp_docx = tempfile.NamedTemporaryFile(delete=False, suffix='.docx')
    try:
        copy_from_env(expected_output, temp_docx.name)
        
        # Verify it's a zip/docx
        if not zipfile.is_zipfile(temp_docx.name):
            return {"passed": False, "score": 0, "feedback": "Output is not a valid DOCX/ZIP file"}
            
        with zipfile.ZipFile(temp_docx.name, 'r') as z:
            xml_content = z.read('word/document.xml')
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse DOCX: {e}"}
    finally:
        if os.path.exists(temp_docx.name): os.unlink(temp_docx.name)

    # 3. Analyze XML
    score = 0
    feedback = []
    
    # Parse XML
    try:
        root = etree.fromstring(xml_content)
        ns = {'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
        text_content = "".join(root.xpath('.//w:t/text()', namespaces=ns))
        
        # --- Check 1: Placeholders Removed (15 pts) ---
        placeholders_remain = []
        for ph in placeholders:
            if ph in text_content:
                placeholders_remain.append(ph)
        
        if not placeholders_remain:
            score += 15
            feedback.append("Placeholders removed")
        else:
            feedback.append(f"Placeholders remaining: {', '.join(placeholders_remain)}")

        # --- Check 2: Captions Exist (25 pts) ---
        # Look for the specific caption text
        found_captions = 0
        for key, text in expected_captions.items():
            # Loose check: "Figure X" and "Text" might be in separate runs, but close in document order
            # Just check if the text exists in the document for now, strict field checking is harder
            if text in text_content:
                found_captions += 1
        
        if found_captions == 3:
            score += 25
            feedback.append("All caption texts found")
        elif found_captions > 0:
            score += 10 * found_captions
            feedback.append(f"Found {found_captions}/3 caption texts")
        else:
            feedback.append("No caption texts found")

        # --- Check 3: Fields for Cross-References (SEQ/REF) (25 pts) ---
        # Look for w:instrText containing "REF"
        instr_texts = root.xpath('.//w:instrText/text()', namespaces=ns)
        ref_fields = [t for t in instr_texts if "REF" in t and "Figure" in t]
        
        # We expect at least 3 REF fields (one for each placeholder)
        if len(ref_fields) >= 3:
            score += 25
            feedback.append(f"Dynamic Cross-References found ({len(ref_fields)})")
        elif len(ref_fields) > 0:
            score += 10
            feedback.append("Some Cross-References found, but fewer than expected")
        else:
            feedback.append("No dynamic Cross-Reference fields found (did you just type the text?)")

        # --- Check 4: Table of Figures (25 pts) ---
        # Look for TOC field with \c switch (e.g., TOC \h \z \c "Figure")
        toc_fields = [t for t in instr_texts if "TOC" in t and "\\c" in t]
        
        if toc_fields:
            score += 25
            feedback.append("Table of Figures found")
        else:
            feedback.append("Table of Figures field not found")

        # --- Check 5: VLM Verification (10 pts) ---
        # Verify visual layout (e.g., table structure at end)
        frames = sample_trajectory_frames(traj, 2)
        final_scr = get_final_screenshot(traj)
        
        vlm_res = query_vlm(
            images=[final_scr],
            prompt="Does this document page show a 'Table of Figures' or 'List of Figures' with page numbers?"
        )
        
        if vlm_res.get('success') and 'yes' in vlm_res.get('result', '').lower():
            score += 10
            feedback.append("Visual verification passed")
        
    except Exception as e:
        feedback.append(f"XML Analysis Error: {e}")

    return {
        "passed": score >= 75,
        "score": score,
        "feedback": " | ".join(feedback)
    }