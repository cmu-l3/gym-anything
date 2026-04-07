#!/usr/bin/env python3
"""
Verifier for generate_tier2_report task.

Checks:
1. File Existence & Metadata: PDF exists, >10KB, created during task.
2. PDF Content: Contains "Valley Industrial", chemical names, etc.
3. VLM Verification: Trajectory shows facility selection and print workflow.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

# Framework imports (assumed available in verifier environment)
try:
    from pdfminer.high_level import extract_text
except ImportError:
    extract_text = None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_generate_tier2_report(traj, env_info, task_info):
    """
    Verify the Tier II PDF report generation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_facility = metadata.get('facility_name', 'Valley Industrial Supply')
    required_chemicals = metadata.get('required_chemicals', [])
    min_size_kb = metadata.get('min_file_size_kb', 10)

    # 1. Retrieve Result JSON from Container
    result_data = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\workspace\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task execution result."}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Retrieve Generated PDF for Content Analysis
    pdf_content = ""
    pdf_retrieved = False
    if result_data.get('output_exists'):
        temp_pdf = tempfile.NamedTemporaryFile(delete=False, suffix='.pdf')
        try:
            # Note: Windows path in container, local path on host
            copy_from_env(result_data['output_path'], temp_pdf.name)
            pdf_retrieved = True
            if extract_text:
                try:
                    pdf_content = extract_text(temp_pdf.name)
                except Exception as e:
                    logger.warning(f"PDF parsing failed: {e}")
        except Exception as e:
            logger.error(f"Failed to copy PDF: {e}")
        finally:
            if os.path.exists(temp_pdf.name):
                os.unlink(temp_pdf.name)

    # --- SCORING ---
    score = 0
    feedback = []

    # Criterion 1: File Existence & Timestamp (30 pts)
    if result_data.get('output_exists'):
        if result_data.get('file_created_during_task'):
            score += 30
            feedback.append("PDF report created during task.")
        else:
            score += 10
            feedback.append("PDF exists but timestamp indicates pre-existence (anti-gaming failure).")
    else:
        feedback.append("Output PDF file not found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Criterion 2: File Size (10 pts)
    size_kb = result_data.get('file_size_bytes', 0) / 1024
    if size_kb >= min_size_kb:
        score += 10
        feedback.append(f"File size valid ({size_kb:.1f} KB).")
    else:
        feedback.append(f"File too small ({size_kb:.1f} KB).")

    # Criterion 3: Content Verification (30 pts)
    content_score = 0
    if pdf_retrieved and pdf_content:
        # Check Facility Name
        if expected_facility.lower() in pdf_content.lower():
            content_score += 10
            feedback.append(f"Found facility '{expected_facility}'.")
        else:
            feedback.append(f"Facility '{expected_facility}' NOT found in PDF.")

        # Check Chemicals
        found_chems = [chem for chem in required_chemicals if chem.lower() in pdf_content.lower()]
        if len(found_chems) >= 2:
            content_score += 20
            feedback.append(f"Found chemicals: {', '.join(found_chems)}.")
        elif len(found_chems) > 0:
            content_score += 10
            feedback.append(f"Found some chemicals: {', '.join(found_chems)}.")
        else:
            feedback.append("No required chemicals found in PDF.")
    elif result_data.get('output_exists'):
        # If we couldn't parse the PDF but it exists and is new, give partial credit or rely on VLM
        feedback.append("Could not parse PDF text for verification.")
    
    score += content_score

    # Criterion 4: VLM Trajectory Verification (30 pts)
    # Using the framework's VLM utility (pseudo-code representation)
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    
    frames = sample_trajectory_frames(traj, n=5)
    
    vlm_prompt = """
    Analyze these screenshots of a user using CAMEO Data Manager.
    Look for the following:
    1. Did the user select "Valley Industrial Supply"?
    2. Did the user open a "Reports" menu or "Tier II" report generation screen?
    3. Did the user see a Print or Save PDF dialog?
    
    Return JSON: {"facility_selected": bool, "report_generated": bool, "print_dialog": bool}
    """
    
    vlm_score = 0
    try:
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        parsed = vlm_res.get('parsed', {})
        
        if parsed.get('facility_selected'):
            vlm_score += 10
            feedback.append("VLM: Facility selection observed.")
        if parsed.get('report_generated'):
            vlm_score += 10
            feedback.append("VLM: Report generation screen observed.")
        if parsed.get('print_dialog'):
            vlm_score += 10
            feedback.append("VLM: Print/Save dialog observed.")
            
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # If VLM fails but file is perfect, we might trust the file
        if score >= 60: 
            vlm_score = 10 # Grace points
            feedback.append("VLM check skipped, trusting file artifact.")

    score += vlm_score

    # Final Check
    passed = (score >= 60) and result_data.get('output_exists') and result_data.get('file_created_during_task')

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback)
    }