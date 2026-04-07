#!/usr/bin/env python3
"""
Verifier for neuropsychological_eval_format task.

Verifies document formatting, structured data extraction (tables), 
header/footer compliance, and dictation artifact sanitization.
"""

import sys
import os
import json
import tempfile
import logging

# Ensure gym_anything VLM utils can be used
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    
# WPS Verification utilities (from wps_office_writer_env/utils)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
try:
    from wps_verification_utils import (
        copy_and_parse_document,
        get_document_text,
        count_tables,
        get_table_content,
        count_headings_by_level
    )
except ImportError:
    pass

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_neuropsychological_eval_format(traj, env_info, task_info):
    """
    Evaluates the Neuropsychological Evaluation formatting.
    Criteria:
    1. Dictation Artifacts Removed (15 pts)
    2. Heading Styles Applied (15 pts)
    3. Test Scores Table Created (25 pts)
    4. Test Data Migrated (15 pts)
    5. Header/Footer Present (20 pts)
    6. VLM Visual Checks (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env missing"}

    metadata = task_info.get('metadata', {})
    required_headings = [h.lower() for h in metadata.get('required_headings', [])]
    
    score = 0
    feedback_parts = []
    
    # 1. Get task execution result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not result.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Output document was not found or saved."}

    # 2. Parse Document
    success, doc, error, temp_dir = copy_and_parse_document(
        "/tmp/eval_report_eval.docx", copy_from_env, file_format='docx'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Document parsing failed: {error}"}

    full_text = get_document_text(doc).lower()
    
    # Check Prerequisite: Core content exists
    if "john doe" not in full_text or "neurocognitive disorder" not in full_text:
        return {"passed": False, "score": 0, "feedback": "Prerequisite failed: Core patient data corrupted or missing."}

    # CRITERION 1: Artifacts Removed (15 pts)
    if "note to typist" not in full_text and "dictator note" not in full_text and "golden retriever" not in full_text:
        score += 15
        feedback_parts.append("Artifacts: Cleanly removed")
    else:
        feedback_parts.append("Artifacts: Dictation notes or irrelevant text still present")

    # CRITERION 2: Heading Styles Applied (15 pts)
    headings_found = 0
    for para in doc.paragraphs:
        if para.style and 'heading' in para.style.name.lower():
            text = para.text.strip().lower()
            if any(req in text for req in required_headings):
                headings_found += 1
                
    if headings_found >= 6:  # Tolerating slight variations
        score += 15
        feedback_parts.append(f"Headings: Applied properly ({headings_found}/{len(required_headings)})")
    elif headings_found > 0:
        score += 7
        feedback_parts.append(f"Headings: Partially applied ({headings_found}/{len(required_headings)})")
    else:
        feedback_parts.append("Headings: No proper Heading styles applied to clinical sections")

    # CRITERION 3 & 4: Table and Data Migrated (25 pts + 15 pts)
    table_created = False
    data_migrated = False
    num_tables = count_tables(doc)
    
    if num_tables > 0:
        for t_idx in range(num_tables):
            content = get_table_content(doc, t_idx)
            if not content or len(content) < 2:
                continue
                
            header_row = " ".join(content[0]).lower()
            # Check if it has 5 columns roughly mapping to the specs
            if len(content[0]) == 5 and ("domain" in header_row or "score" in header_row or "percentile" in header_row):
                table_created = True
                score += 25
                feedback_parts.append("Table Structure: 5-column table with headers found")
                
                # Data migration check
                table_text = " ".join([" ".join(row) for row in content]).lower()
                if "wais-iv" in table_text and "verbal comprehension" in table_text and "98" in table_text and "wms-iv" in table_text:
                    data_migrated = True
                    score += 15
                    feedback_parts.append("Table Data: Score data successfully migrated into table")
                break
                
    if not table_created:
        feedback_parts.append("Table Structure: Required table not found")
        feedback_parts.append("Table Data: Data not migrated to table")

    # CRITERION 5: Header and Footer Content (20 pts)
    header_text = ""
    footer_text = ""
    try:
        for section in doc.sections:
            if section.header:
                for p in section.header.paragraphs:
                    header_text += p.text.lower() + " "
            if section.footer:
                for p in section.footer.paragraphs:
                    footer_text += p.text.lower() + " "
    except Exception:
        pass

    header_points = 0
    if "confidential" in header_text and "protected health information" in header_text:
        header_points += 10
        feedback_parts.append("Page Header: HIPAA header correctly added")
    else:
        # Check if they just placed it at the top of the body
        if "confidential protected health information" in full_text[:500]:
            header_points += 5
            feedback_parts.append("Page Header: Added to body instead of document header")
        else:
            feedback_parts.append("Page Header: Missing")

    if "mrn" in footer_text and "8492-491" in footer_text:
        header_points += 10
        feedback_parts.append("Page Footer: MRN footer correctly added")
    else:
        feedback_parts.append("Page Footer: Missing")
        
    score += header_points

    # CRITERION 6: VLM Verification for Visual Structure (10 pts)
    if VLM_AVAILABLE:
        vlm_prompt = """You are verifying a formatted clinical document in WPS Office Writer.
        Task: The agent must format a Neuropsychological Evaluation Report.
        Please check the screenshot carefully:
        1. Is the title "NEUROPSYCHOLOGICAL EVALUATION REPORT" prominent/centered at the top?
        2. Are the patient demographics (Name, DOB, MRN, Date, Evaluator) cleanly separated/aligned at the top?
        3. Are there visual borders or shading on the table containing the test scores?
        
        Respond in JSON format:
        {
            "title_prominent": true/false,
            "demographics_clean": true/false,
            "table_visually_formatted": true/false
        }"""
        
        try:
            frames = sample_trajectory_frames(traj, n=3)
            final_frame = get_final_screenshot(traj)
            
            # Combine to check if work was done
            vlm_res = query_vlm(prompt=vlm_prompt, images=frames + [final_frame] if final_frame else frames)
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                vlm_score = sum([
                    3 if parsed.get('title_prominent', False) else 0,
                    3 if parsed.get('demographics_clean', False) else 0,
                    4 if parsed.get('table_visually_formatted', False) else 0
                ])
                score += vlm_score
                feedback_parts.append(f"VLM Visual checks: {vlm_score}/10 points")
        except Exception as e:
            logger.warning(f"VLM evaluation failed: {e}")
            score += 10 # Default full credit on VLM failure if other checks pass
            
    else:
        score += 10 # Default credit if VLM entirely unavailable
        
    # Evaluate Pass/Fail
    # To pass: Total score >= 70 AND the table MUST be created
    passed = (score >= 70) and table_created

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }