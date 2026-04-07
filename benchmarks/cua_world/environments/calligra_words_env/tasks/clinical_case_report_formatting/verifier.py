#!/usr/bin/env python3
"""Verifier for the clinical_case_report_formatting task."""

import json
import logging
import os
import re
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calligra_verification_utils import (
    check_heading_styles_odt,
    check_paragraph_alignment_odt,
    check_text_bold_odt,
    check_text_font_size_odt,
    cleanup_verification_temp,
    copy_and_parse_document,
    detect_toc_odt,
    get_document_text_odt,
    get_odt_paragraphs,
    get_odt_tables,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _vlm_query(query_vlm, prompt, image=None, images=None):
    if not query_vlm:
        return None
    if not image and not images:
        return None
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result.get("success"):
            return result.get("parsed", {})
    except Exception as e:
        logger.warning(f"VLM query exception: {e}")
    return None

def verify_clinical_case_report_formatting(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    document_path = metadata.get("document_path", "/home/ga/Documents/case_report.odt")

    # Read the export JSON metadata to ensure document was touched during the task
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    file_modified = False
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
            file_modified = result_data.get("file_created_during_task", False)
    except Exception as e:
        logger.warning(f"Could not read task_result.json: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Parse ODT structures via shared utils
    temp_dir, doc_obj, doc_type = copy_and_parse_document(copy_from_env, document_path)
    if temp_dir is None or doc_type != "odt":
        return {"passed": False, "score": 0, "feedback": "Failed to copy or parse ODT document"}

    content_tree, styles_tree = doc_obj

    try:
        score = 0
        feedback_parts = []
        
        # Anti-gaming: Do Nothing Check
        if not file_modified:
            feedback_parts.append("Warning: Document does not appear to have been modified during the task execution.")
            # We don't fail immediately because they might have used keyboard shortcuts perfectly that missed stat time, 
            # but usually it catches "Do Nothing".
            
        # Criterion 1: Title Formatting (10 points)
        title_text = metadata.get("title_text", "Euglycemic Diabetic Ketoacidosis Associated with SGLT2 Inhibitor Use")
        title_pattern = re.escape(title_text)
        title_bold = check_text_bold_odt(content_tree, styles_tree, title_pattern)
        title_sized = check_text_font_size_odt(content_tree, styles_tree, title_pattern, 14.0)

        if title_bold and title_sized:
            score += 10
            feedback_parts.append("Title: bold and >=14pt OK")
        else:
            missing = []
            if not title_bold: missing.append("bold")
            if not title_sized: missing.append(">=14pt")
            feedback_parts.append(f"Title missing: {', '.join(missing)}")

        # Criterion 2: Section Headings (15 points)
        expected_h1 = metadata.get("expected_h1_sections", [])
        h1_matched, h1_total, _ = check_heading_styles_odt(content_tree, styles_tree, expected_h1, 1)
        if h1_matched >= 8:
            score += 15
            feedback_parts.append(f"H1 Sections: {h1_matched}/{h1_total} OK")
        else:
            feedback_parts.append(f"H1 Sections: {h1_matched}/{h1_total} (need 8)")

        # Criterion 3: Body Text Justified (10 points)
        body_samples = metadata.get("body_alignment_samples", [])
        justified_count = 0
        for sample in body_samples:
            matched, _ = check_paragraph_alignment_odt(content_tree, styles_tree, re.escape(sample), "justify")
            if matched > 0:
                justified_count += 1
                
        if justified_count >= 3:
            score += 10
            feedback_parts.append(f"Body Justified: {justified_count}/{len(body_samples)} OK")
        else:
            feedback_parts.append(f"Body Justified: {justified_count}/{len(body_samples)} (need 3)")

        # Criterion 4: Body Font Size >=11pt (8 points)
        font_size_ok = 0
        for sample in body_samples:
            if check_text_font_size_odt(content_tree, styles_tree, re.escape(sample), 11.0):
                font_size_ok += 1
                
        if font_size_ok >= 2:
            score += 8
            feedback_parts.append(f"Body Font Size >=11pt: {font_size_ok}/{len(body_samples)} OK")
        else:
            feedback_parts.append(f"Body Font Size: {font_size_ok}/{len(body_samples)} (need 2)")

        # Criteria 5 & 6: Tables and Row Count (12 + 8 = 20 points)
        tables = get_odt_tables(content_tree)
        if len(tables) >= 2:
            score += 12
            feedback_parts.append(f"Tables: {len(tables)} found OK")
        else:
            feedback_parts.append(f"Tables: {len(tables)} found (need 2)")
            
        max_rows = max([len(t.get("rows", [])) for t in tables]) if tables else 0
        if max_rows >= 5:
            score += 8
            feedback_parts.append(f"Table Row Count: {max_rows} rows OK")
        else:
            feedback_parts.append(f"Table Row Count: {max_rows} rows (need 5)")

        # Criterion 7: Learning Points List (10 points)
        paragraphs = get_odt_paragraphs(content_tree)
        list_items = [p for p in paragraphs if p.get('is_list_item')]
        lp_keywords = metadata.get("learning_points_keywords", [])
        matched_points = sum(1 for kw in lp_keywords if any(kw.lower() in p['text'].lower() for p in list_items))
        
        if matched_points >= 2:
            score += 10
            feedback_parts.append(f"Learning Points List: {matched_points}/{len(lp_keywords)} items OK")
        else:
            feedback_parts.append(f"Learning Points List: {matched_points}/{len(lp_keywords)} items (need 2)")

        # Criterion 8: Table of Contents (10 points)
        if detect_toc_odt(content_tree):
            score += 10
            feedback_parts.append("TOC: Present OK")
        else:
            feedback_parts.append("TOC: Not found")

        # Criterion 9: Content Preservation (10 points)
        full_text = get_document_text_odt(content_tree).lower()
        content_keywords = metadata.get("content_keywords", [])
        keywords_present = sum(1 for kw in content_keywords if kw.lower() in full_text)
        
        if keywords_present >= 4:  # Allowing 1 keyword failure
            score += 10
            feedback_parts.append(f"Content Preservation: {keywords_present}/{len(content_keywords)} OK")
        else:
            feedback_parts.append(f"Content Preservation: {keywords_present}/{len(content_keywords)} (too low)")

        # Criterion 10: VLM Visual Check (7 points)
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=3)
            final_frame = get_final_screenshot(traj)
            
            images_to_check = frames + ([final_frame] if final_frame else [])
            
            if images_to_check and env_info.get("query_vlm"):
                prompt = """You are evaluating a desktop agent performing document formatting in Calligra Words.
The agent was asked to format a clinical case report.

Look at these screenshots from the agent's workflow. Assess the following:
1. Are there signs of professional formatting being applied? Look for:
   - Proper section headings (larger, bold text)
   - Tables inserted and formatted for the lab values or timeline
   - Bulleted or numbered lists for "Learning Points"
   - Justified body text
   - Table of contents generated
   
Return a JSON object:
{
    "professional_formatting_visible": true,
    "tables_visible": true,
    "confidence": "high",
    "reasoning": "Brief explanation of what you see"
}
"""
                vlm_result = _vlm_query(env_info["query_vlm"], prompt, images=images_to_check)
                if vlm_result and vlm_result.get("professional_formatting_visible"):
                    score += 7
                    feedback_parts.append("VLM visual verification: Passed")
                else:
                    feedback_parts.append("VLM visual verification: Failed or not clear")
            else:
                feedback_parts.append("VLM visual verification: Skipped (no images or VLM unavailable)")
        except Exception as e:
            logger.warning(f"VLM check error: {e}")
            feedback_parts.append("VLM visual verification: Error")

        # The pass threshold is 70 points out of 100 possible.
        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
    finally:
        cleanup_verification_temp(temp_dir)