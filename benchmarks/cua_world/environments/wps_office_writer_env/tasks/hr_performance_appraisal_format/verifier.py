#!/usr/bin/env python3
"""
Verifier for hr_performance_appraisal_format task.
Parses the output DOCX to verify table structures, heading styles, formatting, and content extraction.
Includes VLM fallback for visual verification of form appearance.
"""

import sys
import os
import json
import tempfile
import logging

# Import utilities from the environment
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
try:
    from wps_verification_utils import (
        copy_and_parse_document,
        get_document_text,
        count_tables,
        get_table_content,
        get_table_dimensions
    )
except ImportError:
    logging.warning("wps_verification_utils not found. Ensure this runs in the correct environment.")

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def check_table_shading(table, row_idx=0):
    """Check if the specified row in a python-docx table has background shading."""
    try:
        for cell in table.rows[row_idx].cells:
            tc = cell._tc
            tcPr = tc.get_or_add_tcPr()
            shd = tcPr.find('{http://schemas.openxmlformats.org/wordprocessingml/2006/main}shd')
            if shd is not None:
                fill = shd.get('{http://schemas.openxmlformats.org/wordprocessingml/2006/main}fill')
                if fill not in [None, 'auto', '000000', 'FFFFFF', 'clear']:
                    return True
    except Exception as e:
        logger.warning(f"Error checking shading: {e}")
    return False

def verify_hr_appraisal_format(traj, env_info, task_info):
    """
    Verify the formatting of the HR Performance Appraisal Form.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_competencies = metadata.get('competencies', [])

    # Get JSON export info
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            export_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    output_exists = export_result.get('output_exists', False)
    file_created = export_result.get('file_created_during_task', False)

    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "The file formatted_appraisal_form.docx was not saved."}
    if not file_created:
        return {"passed": False, "score": 0, "feedback": "File exists but was not created/modified during the task timeframe (anti-gaming check failed)."}

    # Copy and parse the actual DOCX file
    container_doc_path = "/tmp/formatted_appraisal_form.docx"
    success, doc, error, temp_dir = copy_and_parse_document(
        container_doc_path, copy_from_env, file_format='docx'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Could not parse document: {error}"}

    score = 0
    feedback_parts = []
    
    # 1. Output Exists & Saved Correctly (10 pts)
    score += 10
    feedback_parts.append("File created and parsed successfully.")

    # Process document text and tables
    full_text = get_document_text(doc).lower()
    num_tables = count_tables(doc)
    
    # Identify tables by content instead of strict indexing
    employee_table = None
    rating_table = None
    competency_table = None
    goals_table = None

    for idx, table in enumerate(doc.tables):
        content = get_table_content(doc, idx)
        text_dump = " ".join([" ".join(row).lower() for row in content])
        
        if "job title" in text_dump or "department" in text_dump or "evaluation period" in text_dump:
            employee_table = table
        elif "unacceptable" in text_dump and "outstanding" in text_dump:
            rating_table = table
        elif "accountability" in text_dump and "customer service" in text_dump:
            competency_table = table
        elif "goal description" in text_dump or "success metrics" in text_dump:
            goals_table = table

    # 2. Employee Info Table (15 pts)
    # Expected: 2 columns, 3 rows
    if employee_table:
        rows = len(employee_table.rows)
        cols = len(employee_table.columns) if rows > 0 else 0
        if rows == 3 and cols == 2:
            score += 15
            feedback_parts.append("Employee Info table has correct dimensions (2x3).")
        elif rows >= 2 and cols >= 2:
            score += 10
            feedback_parts.append(f"Employee Info table found but dimensions are {cols}x{rows} instead of 2x3.")
        else:
            score += 5
            feedback_parts.append("Employee Info table found but poorly structured.")
    else:
        feedback_parts.append("Employee Info table NOT found.")

    # 3. Rating Scale Table (15 pts) & Shading (5 pts)
    # Expected: 5 columns, 2 rows
    if rating_table:
        rows = len(rating_table.rows)
        cols = len(rating_table.columns) if rows > 0 else 0
        if rows == 2 and cols == 5:
            score += 15
            feedback_parts.append("Rating Scale table has correct dimensions (5x2).")
        elif cols >= 5:
            score += 10
            feedback_parts.append(f"Rating Scale table dimensions partial match ({cols}x{rows}).")
        else:
            score += 5
            feedback_parts.append("Rating Scale table found but lacks columns.")

        # Check Shading (5 pts)
        if check_table_shading(rating_table, row_idx=0):
            score += 5
            feedback_parts.append("Rating Scale header shading applied.")
        else:
            feedback_parts.append("Rating Scale header shading NOT detected.")
    else:
        feedback_parts.append("Rating Scale table NOT found.")

    # 4. Core Competencies Table (20 pts)
    # Expected: 4 columns, 9 rows (header + 8 competencies)
    if competency_table:
        rows = len(competency_table.rows)
        cols = len(competency_table.columns) if rows > 0 else 0
        
        # Check extraction
        found_comps = 0
        t_content = " ".join([" ".join(c.text.lower() for c in r.cells) for r in competency_table.rows])
        for c in expected_competencies:
            if c.lower() in t_content:
                found_comps += 1

        if cols >= 4 and rows >= 9:
            score += 10
            feedback_parts.append("Competency table has correct dimensions (>= 4x9).")
        elif cols >= 4:
            score += 5
            feedback_parts.append("Competency table has correct columns but missing rows.")
        
        if found_comps >= 7:
            score += 10
            feedback_parts.append(f"Competencies successfully extracted to table ({found_comps}/8).")
        elif found_comps >= 4:
            score += 5
            feedback_parts.append(f"Partial competencies extracted to table ({found_comps}/8).")
        else:
            feedback_parts.append(f"Failed to extract competencies to table ({found_comps}/8).")
    else:
        feedback_parts.append("Core Competencies table NOT found.")

    # 5. Future Goals Table (10 pts)
    # Expected: 3 columns, 4 rows
    if goals_table:
        rows = len(goals_table.rows)
        cols = len(goals_table.columns) if rows > 0 else 0
        if cols >= 3 and rows >= 4:
            score += 10
            feedback_parts.append("Future Goals table has correct dimensions (>= 3x4).")
        elif cols >= 3:
            score += 5
            feedback_parts.append("Future Goals table has correct columns but lacking blank rows.")
        else:
            feedback_parts.append("Future Goals table found but poorly structured.")
    else:
        feedback_parts.append("Future Goals table NOT found.")

    # 6. Title formatting & Signatures (10 pts)
    title_correct = False
    for p in doc.paragraphs[:5]:
        if "Annual Performance Appraisal" in p.text and p.style and 'title' in p.style.name.lower():
            title_correct = True
            break
    if title_correct:
        score += 5
        feedback_parts.append("Title style applied correctly.")
    
    if "employee signature" in full_text and "manager signature" in full_text:
        score += 5
        feedback_parts.append("Signature block keywords present.")
    else:
        feedback_parts.append("Signature block missing.")

    # 7. Font Enforcement (Arial 11pt) (10 pts)
    total_runs = 0
    arial_runs = 0
    pt11_runs = 0

    def check_run(r, p):
        nonlocal total_runs, arial_runs, pt11_runs
        if r.text.strip():
            total_runs += 1
            font_name = r.font.name if r.font.name else (p.style.font.name if p.style and p.style.font else None)
            font_size = r.font.size.pt if r.font.size else (p.style.font.size.pt if p.style and p.style.font and p.style.font.size else None)
            
            if font_name and 'arial' in font_name.lower():
                arial_runs += 1
            if font_size == 11.0:
                pt11_runs += 1

    for p in doc.paragraphs:
        for r in p.runs: check_run(r, p)
    for t in doc.tables:
        for row in t.rows:
            for cell in row.cells:
                for p in cell.paragraphs:
                    for r in p.runs: check_run(r, p)
    
    if total_runs > 0:
        arial_ratio = arial_runs / total_runs
        pt11_ratio = pt11_runs / total_runs
        if arial_ratio > 0.8 and pt11_ratio > 0.8:
            score += 10
            feedback_parts.append("Arial 11pt consistently applied.")
        elif arial_ratio > 0.5 or pt11_ratio > 0.5:
            score += 5
            feedback_parts.append("Arial 11pt partially applied.")
        else:
            feedback_parts.append("Font formatting not consistently applied to Arial 11pt.")

    # VLM Verification (Visual Check of Form Aesthetics)
    try:
        frames = sample_trajectory_frames(traj, n=3)
        final_img = get_final_screenshot(traj)
        if final_img:
            images = frames + [final_img]
            vlm_prompt = """Look at these screenshots of a word processor. 
            Did the user successfully convert a messy block of text into a professional, multi-table performance appraisal form?
            You should see distinct grids/tables for Employee Info, Rating Scale, Core Competencies, and Future Goals.
            Does the document look like a clean form intended for data entry?
            Reply with JSON containing "is_structured_form" (boolean) and "reasoning" (string)."""
            
            vlm_result = query_vlm(images=images, prompt=vlm_prompt)
            if vlm_result.get("success") and vlm_result.get("parsed", {}).get("is_structured_form"):
                score = min(100, score + 0) # Use as validation/tiebreaker rather than core points
                feedback_parts.append("VLM visual verification passed.")
            elif vlm_result.get("success"):
                feedback_parts.append(f"VLM raised concerns: {vlm_result.get('parsed', {}).get('reasoning')}")
    except Exception as e:
        logger.warning(f"VLM verification skipped or failed: {e}")

    passed = score >= 80 and (competency_table is not None)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }