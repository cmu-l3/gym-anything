#!/usr/bin/env python3
"""
Verifier for the chemistry_midterm_formatting task.

Checks:
1. File modified check (Anti-gaming)
2. Exam Title bold and >=14pt (10)
3. Course Info bold (10)
4. Section Headings (15)
5. Point Allocation Table (15)
6. Constants Table (10)
7. Body font size >=11pt (10)
8. Content preservation (10)
9. Title centered (5)
10. MC Options formatted correctly (5)
11. VLM trajectory check (10)

Total 100, passing >= 60.
"""

import json
import logging
import os
import re
import sys
import tempfile

# Import shared verification utilities
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calligra_verification_utils import (
    check_heading_styles_odt,
    check_paragraph_alignment_odt,
    check_text_bold_odt,
    check_text_font_size_odt,
    copy_and_parse_document,
    get_document_text_odt,
    get_odt_paragraphs,
    get_odt_tables,
    get_odt_styles
)
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _vlm_query(query_vlm, prompt, images):
    """Helper to query VLM and return parsed JSON."""
    if not query_vlm or not images:
        return None
    try:
        result = query_vlm(prompt=prompt, images=images)
        if result.get("success"):
            return result.get("parsed", {})
        logger.warning(f"VLM query failed: {result.get('error', 'unknown')}")
    except Exception as e:
        logger.warning(f"VLM query exception: {e}")
    return None


def verify_chemistry_midterm(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    query_vlm = env_info.get("query_vlm")
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    document_path = metadata.get("document_path", "/home/ga/Documents/chem1311_midterm.odt")

    # 1. Read export result to check if file was modified
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            export_data = json.load(f)
    except Exception as e:
        export_data = {"file_modified_during_task": False}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if not export_data.get("file_modified_during_task", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Document was not modified or saved during the task."
        }

    # 2. Copy and parse the ODT document
    temp_dir, doc_obj, doc_type = copy_and_parse_document(copy_from_env, document_path)
    if temp_dir is None or doc_type != "odt":
        return {"passed": False, "score": 0, "feedback": "Failed to copy or parse ODT document"}

    content_tree, styles_tree = doc_obj
    
    score = 0
    feedback_parts = []
    
    # Extract complete text and tables for checks
    full_text = get_document_text_odt(content_tree)
    full_text_lower = full_text.lower()
    tables = get_odt_tables(content_tree)
    paragraphs = get_odt_paragraphs(content_tree)

    # ── Criterion: Exam Title (10 points) ──
    # Bold and >=14pt
    title_pattern = re.escape(metadata.get("expected_title", "Midterm Examination"))
    title_bold = check_text_bold_odt(content_tree, styles_tree, title_pattern)
    title_sized = check_text_font_size_odt(content_tree, styles_tree, title_pattern, 14.0)
    
    if title_bold and title_sized:
        score += 10
        feedback_parts.append("Title bold and >=14pt (+10)")
    else:
        feedback_parts.append("Title missing bold or size >=14pt")

    # ── Criterion: Title Centered (5 points) ──
    title_centered, _ = check_paragraph_alignment_odt(
        content_tree, styles_tree, title_pattern, "center"
    )
    if title_centered > 0:
        score += 5
        feedback_parts.append("Title centered (+5)")
    else:
        feedback_parts.append("Title not centered")

    # ── Criterion: Course Info (10 points) ──
    # Bold
    course_pattern = re.escape(metadata.get("expected_course", "CHEM 1311"))
    course_bold = check_text_bold_odt(content_tree, styles_tree, course_pattern)
    if course_bold:
        score += 10
        feedback_parts.append("Course info bold (+10)")
    else:
        feedback_parts.append("Course info not bold")

    # ── Criterion: Section Headings (15 points) ──
    expected_headings = metadata.get("expected_headings", [])
    # Can be level 1, 2, or 3
    h_matched_1, _, _ = check_heading_styles_odt(content_tree, styles_tree, expected_headings, 1)
    h_matched_2, _, _ = check_heading_styles_odt(content_tree, styles_tree, expected_headings, 2)
    h_matched_3, _, _ = check_heading_styles_odt(content_tree, styles_tree, expected_headings, 3)
    
    total_h_matched = max(h_matched_1, h_matched_2, h_matched_3)
    if total_h_matched >= 2:
        score += 15
        feedback_parts.append(f"Section headings formatted: {total_h_matched}/{len(expected_headings)} (+15)")
    else:
        feedback_parts.append(f"Section headings insufficient: {total_h_matched}/{len(expected_headings)}")

    # ── Criterion: Tables for Points and Constants (15 + 10 points) ──
    point_kws = metadata.get("point_table_keywords", ["30", "40", "100"])
    const_kws = metadata.get("constants_table_keywords", ["8.314", "6.022"])
    
    has_point_table = False
    has_const_table = False
    
    for tbl in tables:
        tbl_text = ""
        for row in tbl.get("rows", []):
            tbl_text += " ".join(row).lower() + " "
            
        # Check if it has at least 3 rows (standard table check)
        if len(tbl.get("rows", [])) >= 3:
            if any(kw in tbl_text for kw in point_kws) and "part i" in tbl_text:
                has_point_table = True
            if any(kw in tbl_text for kw in const_kws) and "r" in tbl_text:
                has_const_table = True

    if has_point_table:
        score += 15
        feedback_parts.append("Point allocation table found (+15)")
    else:
        feedback_parts.append("Point allocation table missing/invalid")
        
    if has_const_table:
        score += 10
        feedback_parts.append("Constants reference table found (+10)")
    else:
        feedback_parts.append("Constants reference table missing/invalid")

    # ── Criterion: Body Font Size (10 points) ──
    body_samples = metadata.get("body_samples", [])
    font_size_ok = 0
    for sample in body_samples:
        if check_text_font_size_odt(content_tree, styles_tree, re.escape(sample), 11.0):
            font_size_ok += 1
            
    if len(body_samples) > 0 and font_size_ok >= 2:
        score += 10
        feedback_parts.append(f"Body font size >=11pt: {font_size_ok}/{len(body_samples)} (+10)")
    else:
        feedback_parts.append(f"Body font size <11pt: {font_size_ok}/{len(body_samples)}")

    # ── Criterion: Content Preservation (10 points) ──
    content_keywords = metadata.get("content_keywords", [])
    kw_found = sum(1 for kw in content_keywords if kw.lower() in full_text_lower)
    if kw_found >= 7:
        score += 10
        feedback_parts.append(f"Content preserved: {kw_found}/{len(content_keywords)} (+10)")
    else:
        feedback_parts.append(f"Content truncated: only {kw_found}/{len(content_keywords)} keywords found")

    # ── Criterion: Multiple Choice Structure (5 points) ──
    # Check if A, B, C, D exist distinctly in the document structure.
    # The agent might use lists, or might keep them as paragraphs.
    mc_option_patterns = [r"A[).]\s", r"B[).]\s", r"C[).]\s", r"D[).]\s"]
    mc_matches = 0
    for pattern in mc_option_patterns:
        if len(re.findall(pattern, full_text, flags=re.IGNORECASE)) >= 5:
            mc_matches += 1
            
    if mc_matches == 4: # Found all 4 options (A-D) repeatedly
        score += 5
        feedback_parts.append("MC options properly structured (+5)")
    else:
        feedback_parts.append("MC options structure disrupted")

    # ── Criterion: VLM Visual Check (10 points) ──
    frames = sample_trajectory_frames(traj, n=3)
    final_img = get_final_screenshot(traj)
    images_to_check = frames + [final_img] if final_img else frames

    vlm_prompt = """You are evaluating screenshots of an agent formatting a chemistry midterm exam in a word processor.

Assess the visual layout:
1. EXAM_LAYOUT: Does the final document visually resemble an exam? (Distinct title/header, clear sections, readable text).
2. ACTIVE_FORMATTING: Do the trajectory frames show the agent actively making formatting changes (selecting text, changing fonts, creating tables)?

Respond strictly in JSON:
{
    "exam_layout_visible": true/false,
    "active_formatting_observed": true/false
}
"""
    vlm_result = _vlm_query(query_vlm, vlm_prompt, images_to_check)
    if vlm_result:
        if vlm_result.get("exam_layout_visible", False) and vlm_result.get("active_formatting_observed", False):
            score += 10
            feedback_parts.append("VLM visual layout verified (+10)")
        else:
            feedback_parts.append("VLM visual verification failed")
    else:
        # Give partial credit if VLM fails to respond but document was modified
        score += 5
        feedback_parts.append("VLM query failed (partial credit +5)")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }