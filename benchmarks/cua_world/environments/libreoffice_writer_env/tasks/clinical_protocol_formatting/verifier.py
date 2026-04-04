#!/usr/bin/env python3
"""
Verifier for Clinical Protocol Formatting Task.
Checks DOCX structure for hospital standards compliance.
"""

import json
import os
import logging
import sys
import shutil

# Add utils path to import writer_verification_utils
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
try:
    from writer_verification_utils import (
        copy_and_parse_document,
        check_heading_styles,
        check_paragraph_alignment,
        cleanup_verification_temp
    )
except ImportError:
    # Fallback if utils not immediately found (e.g. running locally)
    logging.warning("writer_verification_utils not found, some checks may fail")

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_clinical_protocol(traj, env_info, task_info):
    """
    Verifies the formatted sepsis protocol document.
    
    Criteria:
    1. File creation/validity (Gateway)
    2. Font: Liberation Sans/Arial, 11pt
    3. Margins: 1.0 inch
    4. Headings: Styles applied (Heading 1, Heading 2)
    5. Title: Center aligned
    6. Line Spacing: 1.15
    7. Header: Presence of hospital header
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function missing"}

    # --- 1. Retrieve Result JSON ---
    import tempfile
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    try:
        copy_from_env("/tmp/task_result.json", temp_json)
        with open(temp_json, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task status: {e}"}
    finally:
        if os.path.exists(temp_json):
            os.unlink(temp_json)

    if not result_data.get("file_exists") or not result_data.get("file_created_during_task"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output file /home/ga/Documents/sepsis_protocol_formatted.docx was not found or not modified."
        }

    # --- 2. Retrieve and Parse DOCX ---
    # Use helper from utils if available, or manual extraction
    container_path = result_data["output_path"]
    success, doc, error_msg, temp_dir = copy_and_parse_document(
        container_path, copy_from_env, file_format='docx'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse document: {error_msg}"}

    try:
        score = 0
        feedback = []
        
        # --- CRITERION 1: MARGINS (1.0 inch) ---
        # 1 inch = 914400 EMU. Tolerance +/- 0.065" (~60000 EMU)
        target_emu = 914400
        tolerance = 60000
        margins_ok = True
        try:
            section = doc.sections[0]
            for m_name in ['left', 'right', 'top', 'bottom']:
                val = getattr(section, f"{m_name}_margin")
                if val is None or abs(val - target_emu) > tolerance:
                    margins_ok = False
                    feedback.append(f"Margin {m_name} incorrect (found {val}, expected ~{target_emu})")
        except Exception:
            margins_ok = False
            feedback.append("Could not verify margins")
            
        if margins_ok:
            score += 15
            feedback.append("Margins correct (1.0 inch)")

        # --- CRITERION 2: HEADING STYLES (Heading 1 & 2) ---
        expected_h1 = task_info['metadata']['heading_1_sections']
        h1_map = {txt: 'Heading 1' for txt in expected_h1}
        
        # We also look for H2 (subsections)
        # We don't have exact list in metadata for H2, but we can look for "Fluid Resuscitation" etc.
        expected_h2 = ["qSOFA", "Hour-1 Bundle", "Administration Timing", "Empiric Selection", 
                       "Fluid Resuscitation", "Vasopressor Therapy", "Mechanical Ventilation"]
        h2_map = {txt: 'Heading 2' for txt in expected_h2}
        
        matched_h1, total_h1, _ = check_heading_styles(doc, h1_map)
        matched_h2, total_h2, _ = check_heading_styles(doc, h2_map)
        
        # 15 pts for H1
        if matched_h1 >= len(expected_h1) - 2: # Allow 2 misses
            score += 15
            feedback.append(f"Major headings styles applied ({matched_h1}/{len(expected_h1)})")
        else:
            feedback.append(f"Major headings missing styles ({matched_h1}/{len(expected_h1)})")

        # 10 pts for H2
        if matched_h2 >= len(expected_h2) - 2:
            score += 10
            feedback.append(f"Subsection styles applied ({matched_h2}/{len(expected_h2)})")

        # --- CRITERION 3: FONT (Liberation Sans/Arial 11pt) ---
        # We iterate over body paragraphs (not headings)
        approved_fonts = ['liberation sans', 'arial', 'helvetica']
        valid_runs = 0
        total_runs = 0
        valid_size = 0
        
        for p in doc.paragraphs:
            if p.style.name.startswith('Heading') or p.style.name.startswith('Title'):
                continue
            if not p.text.strip():
                continue
                
            for run in p.runs:
                if not run.text.strip():
                    continue
                total_runs += 1
                
                # Check Font Name
                f_name = run.font.name
                if f_name is None: 
                    # Fallback to style font if run font is None
                    f_name = p.style.font.name if p.style and p.style.font else None
                
                if f_name and any(af in f_name.lower() for af in approved_fonts):
                    valid_runs += 1
                
                # Check Font Size (11pt)
                f_size = run.font.size
                if f_size is None:
                    f_size = p.style.font.size if p.style and p.style.font else None
                
                # 11pt is 140970 EMU approx, or Pt(11)
                # Allow slight float tolerance
                if f_size and 10.5 <= f_size.pt <= 11.5:
                    valid_size += 1

        font_score = 0
        if total_runs > 0:
            if (valid_runs / total_runs) > 0.5:
                font_score += 15
                feedback.append("Font family correct")
            else:
                feedback.append(f"Font family incorrect ({valid_runs}/{total_runs} runs)")
                
            if (valid_size / total_runs) > 0.5:
                font_score += 15
                feedback.append("Font size correct")
            else:
                feedback.append(f"Font size incorrect ({valid_size}/{total_runs} runs)")
        score += font_score

        # --- CRITERION 4: TITLE ALIGNMENT (Center) ---
        # Find the title paragraph
        title_ok = False
        for p in doc.paragraphs:
            if "Sepsis Management Clinical Protocol" in p.text:
                # Check alignment enum (CENTER=1)
                if p.alignment == 1: # WD_ALIGN_PARAGRAPH.CENTER
                    title_ok = True
                break
        
        if title_ok:
            score += 10
            feedback.append("Title centered")
        else:
            feedback.append("Title not centered")

        # --- CRITERION 5: LINE SPACING (1.15) ---
        # 1.15 spacing usually stored as float 1.15 OR Rule 'multiple'
        spacing_ok_count = 0
        body_para_count = 0
        for p in doc.paragraphs:
            if not p.text.strip() or p.style.name.startswith('Heading'): continue
            body_para_count += 1
            
            ls = p.paragraph_format.line_spacing
            # Check for 1.15 float or ~276 line spacing rule if exact
            if ls and isinstance(ls, float) and 1.1 <= ls <= 1.2:
                spacing_ok_count += 1
        
        if body_para_count > 0 and (spacing_ok_count / body_para_count) > 0.5:
            score += 10
            feedback.append("Line spacing correct")
        else:
            feedback.append("Line spacing incorrect")

        # --- CRITERION 6: HEADER PRESENCE ---
        header_text = ""
        try:
            for p in doc.sections[0].header.paragraphs:
                header_text += p.text
        except:
            pass
            
        if "Memorial" in header_text and "Clinical Protocol" in header_text:
            score += 10
            feedback.append("Header present")
        else:
            feedback.append("Header missing or incorrect")

        return {
            "passed": score >= 65,
            "score": score,
            "feedback": " | ".join(feedback)
        }

    finally:
        cleanup_verification_temp(temp_dir)