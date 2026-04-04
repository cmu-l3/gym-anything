#!/usr/bin/env python3
"""
Verifier for chem_inventory_formatting task.
"""

import sys
import os
import logging
import json
import tempfile
import re

# Add utils directory to path to import writer utilities
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from writer_verification_utils import (
    copy_and_parse_document,
    cleanup_verification_temp,
    get_document_text,
    vlm_verify_screenshot
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_chem_inventory_formatting(traj, env_info, task_info):
    """
    Verify chemical inventory formatting task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Documents/chem_inventory_formatted.docx')
    target_formulas = metadata.get('target_formulas', {})
    target_ions = metadata.get('target_ions', {})
    section_headings = metadata.get('section_headings', [])
    signal_words = metadata.get('signal_words', [])

    # 1. Load the document
    success, doc, error, temp_dir = copy_and_parse_document(output_path, copy_from_env, file_format='docx')
    
    if not success:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Could not open output file: {error}. Did you save as {output_path}?"
        }

    score = 0
    feedback_parts = []
    
    # --- Check 1: Section Headings (Heading 1) ---
    # Max Points: 20
    headings_found = 0
    headings_correct = 0
    
    for para in doc.paragraphs:
        text = para.text.strip()
        if text in section_headings:
            headings_found += 1
            if para.style and 'Heading 1' in para.style.name:
                headings_correct += 1
    
    if headings_correct >= 3:
        score += 20
        feedback_parts.append(f"Headings: Correct ({headings_correct}/{len(section_headings)})")
    elif headings_correct > 0:
        score += 10
        feedback_parts.append(f"Headings: Partial ({headings_correct}/{len(section_headings)} styled)")
    else:
        feedback_parts.append("Headings: No 'Heading 1' styles applied")

    # --- Check 2: Signal Words (Bold) ---
    # Max Points: 15
    bold_words_found = 0
    for para in doc.paragraphs:
        for word in signal_words:
            if word in para.text:
                # Check runs for bold
                is_bold = False
                # Simple check: if any run containing part of the word is bold
                # A more robust check iterates runs, but this usually suffices for whole words
                for run in para.runs:
                    if word in run.text and run.bold:
                        is_bold = True
                        break
                    # Handle split runs (e.g. DANG-ER)
                    if run.bold and run.text in word and len(run.text) > 1:
                         # Heuristic: if a bold run is part of the signal word
                         is_bold = True 
                
                if is_bold:
                    bold_words_found += 1

    if bold_words_found >= 3:
        score += 15
        feedback_parts.append("Signal Words: All bold")
    elif bold_words_found > 0:
        score += 5 * bold_words_found
        feedback_parts.append(f"Signal Words: {bold_words_found}/3 bold")
    else:
        feedback_parts.append("Signal Words: Not bolded")

    # --- Check 3: Subscripts in Table Formulas ---
    # Max Points: 25
    # We need to find the table with formulas
    formulas_checked = 0
    formulas_correct = 0
    
    # Iterate all tables, looking for formula column
    for table in doc.tables:
        for row in table.rows:
            # Check cell 1 (Formula column)
            if len(row.cells) > 1:
                cell_text = row.cells[1].text.strip()
                if cell_text in target_formulas:
                    formulas_checked += 1
                    indices_to_sub = target_formulas[cell_text]
                    
                    # Verify formatting of characters at specific indices
                    # We must reconstruct runs to map indices
                    current_idx = 0
                    all_subs_correct = True
                    
                    # Flatten runs in the cell
                    runs = []
                    for p in row.cells[1].paragraphs:
                        runs.extend(p.runs)
                    
                    for run in runs:
                        run_text = run.text
                        run_len = len(run_text)
                        
                        # Check if any character in this run falls into a target index
                        run_start = current_idx
                        run_end = current_idx + run_len
                        
                        for target_idx in indices_to_sub:
                            if run_start <= target_idx < run_end:
                                # This run contains a character that should be subscript
                                if not run.font.subscript:
                                    all_subs_correct = False
                        
                        current_idx += run_len
                    
                    if all_subs_correct:
                        formulas_correct += 1

    if formulas_correct >= 8: # Allow minor errors
        score += 25
        feedback_parts.append(f"Formulas: Excellent ({formulas_correct}/{formulas_checked})")
    elif formulas_correct >= 5:
        score += 15
        feedback_parts.append(f"Formulas: Good ({formulas_correct}/{formulas_checked})")
    elif formulas_correct > 0:
        score += 5
        feedback_parts.append(f"Formulas: Poor ({formulas_correct}/{formulas_checked})")
    else:
        feedback_parts.append("Formulas: No subscripts detected")

    # --- Check 4: Superscripts in Ionic Species ---
    # Max Points: 20
    ions_found = 0
    ions_correct = 0
    
    # Find the paragraph with ions
    for para in doc.paragraphs:
        # Check text "Na+, Ca2+" etc
        if "Na+" in para.text or "Cl-" in para.text:
            # Check runs
            current_idx = 0
            runs = para.runs
            full_text = para.text
            
            # Locate ions in full text
            for ion, charge_str in target_ions.items():
                start_search = 0
                while True:
                    found_idx = full_text.find(ion, start_search)
                    if found_idx == -1:
                        break
                    
                    # Calculate where the charge part starts in the string
                    # e.g. Ca2+: charge "2+" starts at index 2 of "Ca2+"
                    charge_start_rel = ion.find(charge_str)
                    abs_charge_start = found_idx + charge_start_rel
                    abs_charge_end = abs_charge_start + len(charge_str)
                    
                    # Check runs covering this range
                    run_cursor = 0
                    ion_is_super = True
                    
                    for run in runs:
                        r_start = run_cursor
                        r_end = run_cursor + len(run.text)
                        
                        # Intersection of run and charge string
                        intersect_start = max(r_start, abs_charge_start)
                        intersect_end = min(r_end, abs_charge_end)
                        
                        if intersect_start < intersect_end:
                            # This run contains part of the charge
                            if not run.font.superscript:
                                ion_is_super = False
                        
                        run_cursor += len(run.text)
                    
                    if ion_is_super:
                        ions_correct += 1
                    ions_found += 1
                    
                    start_search = found_idx + 1

    if ions_correct >= 4:
        score += 20
        feedback_parts.append(f"Ions: Correct ({ions_correct} found)")
    elif ions_correct > 0:
        score += 10
        feedback_parts.append(f"Ions: Partial ({ions_correct} correct)")
    else:
        feedback_parts.append("Ions: No superscripts detected")

    # --- Check 5: File existence and integrity (Base points) ---
    # Max Points: 10
    score += 10
    feedback_parts.append("File: Exists and parseable")
    
    # --- Check 6: VLM Verification (Visual Confirmation) ---
    # Max Points: 10
    # Use VLM to catch visual formatting that might be technically weird in XML but look right,
    # or to verify the overall layout.
    vlm_prompt = """
    Look at this document screenshot.
    1. Are the section titles (like 'Compound Inventory') larger/bold (Headings)?
    2. Do the chemical formulas in the table look like H₂O (numbers small and low)?
    3. Do the ions look like Ca²⁺ (numbers/signs small and high)?
    4. Are DANGER/WARNING bolded?
    Answer JSON: {"headings_visible": bool, "subscripts_visible": bool, "superscripts_visible": bool}
    """
    vlm_result = vlm_verify_screenshot(env_info, traj, vlm_prompt)
    if vlm_result.get('parsed', {}).get('subscripts_visible', False):
        score += 5
    if vlm_result.get('parsed', {}).get('headings_visible', False):
        score += 5

    # Cleanup
    cleanup_verification_temp(temp_dir)

    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }