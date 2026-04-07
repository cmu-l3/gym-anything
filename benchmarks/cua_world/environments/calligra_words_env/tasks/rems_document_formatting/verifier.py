#!/usr/bin/env python3
"""Verifier for the rems_document_formatting task."""

import logging
import os
import re
import sys
import json

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calligra_verification_utils import (
    check_heading_styles_odt,
    check_paragraph_alignment_odt,
    check_text_bold_odt,
    check_text_font_size_odt,
    cleanup_verification_temp,
    copy_and_parse_document,
    get_document_text_odt,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

ODF_NS = {
    'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
    'table': 'urn:oasis:names:tc:opendocument:xmlns:table:1.0',
    'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0'
}

def verify_rems_document_formatting(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    document_path = metadata.get("document_path", "/home/ga/Documents/mycophenolate_rems_draft.odt")

    # Read output using safe environment copy functionality
    temp_dir, doc_obj, doc_type = copy_and_parse_document(copy_from_env, document_path)
    if temp_dir is None or doc_type != "odt":
        return {"passed": False, "score": 0, "feedback": "Failed to copy or parse ODT document"}

    content_tree, styles_tree = doc_obj

    try:
        score = 0
        feedback_parts = []
        
        # ── 1. Title Formatting (10 pts) ──
        title_text = metadata.get("title_text", "Mycophenolate Shared System REMS")
        title_pattern = re.escape(title_text)
        
        title_bold = check_text_bold_odt(content_tree, styles_tree, title_pattern)
        title_sized = check_text_font_size_odt(content_tree, styles_tree, title_pattern, 16.0)
        title_centered, _ = check_paragraph_alignment_odt(content_tree, styles_tree, title_pattern, "center")
        
        title_score = 0
        if title_bold: title_score += 4
        if title_sized: title_score += 3
        if title_centered > 0: title_score += 3
        
        score += title_score
        feedback_parts.append(f"Title formatted: {title_score}/10 pts")

        # ── 2. Black Box Warning 1x1 Table (25 pts) ──
        bb_warning_found = False
        tables = content_tree.findall('.//table:table', ODF_NS)
        for tbl in tables:
            rows = tbl.findall('./table:table-row', ODF_NS)
            # Must be exactly 1 row
            if len(rows) == 1:
                cells = rows[0].findall('./table:table-cell', ODF_NS)
                # Must be exactly 1 column
                if len(cells) == 1:
                    cell_text = "".join(cells[0].itertext())
                    if "EMBRYO-FETAL TOXICITY" in cell_text:
                        bb_warning_found = True
                        break
        
        if bb_warning_found:
            score += 25
            feedback_parts.append("Black Box Warning 1x1 table found: 25/25 pts")
        else:
            feedback_parts.append("Black Box Warning 1x1 table NOT found: 0/25 pts")

        # ── 3. Heading Hierarchy (20 pts) ──
        h1_sections = metadata.get("h1_sections", [])
        h1_matched, h1_total, _ = check_heading_styles_odt(content_tree, styles_tree, h1_sections, 1)
        
        h2_sections = metadata.get("h2_sections", [])
        h2_matched, h2_total, _ = check_heading_styles_odt(content_tree, styles_tree, h2_sections, 2)
        
        h1_score = int(10 * (h1_matched / max(1, h1_total)))
        h2_score = int(10 * (h2_matched / max(1, h2_total)))
        score += h1_score + h2_score
        feedback_parts.append(f"Headings H1: {h1_matched}/{h1_total}, H2: {h2_matched}/{h2_total} ({h1_score+h2_score}/20 pts)")

        # ── 4. Bulleted Lists (15 pts) ──
        required_bullets = [
            "Must be certified in the Mycophenolate REMS",
            "Must counsel patients on the risk",
            "Understand the risks of birth defects",
            "Verify the prescriber is certified"
        ]
        list_items = content_tree.findall('.//text:list-item', ODF_NS)
        bullets_found = 0
        for req in required_bullets:
            found = False
            for item in list_items:
                item_text = "".join(item.itertext())
                if req.lower() in item_text.lower():
                    found = True
                    break
            if found:
                bullets_found += 1
                
        list_score = int(15 * (bullets_found / len(required_bullets)))
        score += list_score
        feedback_parts.append(f"Bulleted lists: {bullets_found}/{len(required_bullets)} ({list_score}/15 pts)")

        # ── 5. Assessment Timetable (15 pts) ──
        timetable_found = False
        for tbl in tables:
            rows = tbl.findall('./table:table-row', ODF_NS)
            if len(rows) >= 2:
                # Check for 2+ columns by looking at the first row
                cells = rows[0].findall('./table:table-cell', ODF_NS)
                if len(cells) >= 2:
                    table_text = "".join(tbl.itertext())
                    if "1st Assessment" in table_text and "18 Months" in table_text:
                        timetable_found = True
                        break
        
        if timetable_found:
            score += 15
            feedback_parts.append("Assessment timetable found: 15/15 pts")
        else:
            feedback_parts.append("Assessment timetable NOT found: 0/15 pts")

        # ── 6. Content Preservation (5 pts) ──
        full_text = get_document_text_odt(content_tree)
        word_count = len(full_text.split())
        # The original document has ~220 words.
        if word_count > 180:
            score += 5
            feedback_parts.append("Content preserved: 5/5 pts")
        else:
            feedback_parts.append(f"Content significantly reduced (words={word_count}): 0/5 pts")

        # ── 7. VLM Visual Verification (10 pts) ──
        vlm_score = 0
        query_vlm = env_info.get("query_vlm")
        if query_vlm:
            try:
                from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
                frames = sample_trajectory_frames(traj, n=3)
                final = get_final_screenshot(traj)
                images = frames + [final] if final else frames
                
                if images:
                    prompt = """You are evaluating a word processing task where an agent is formatting an FDA REMS document.
Check the sequence of screenshots to determine if the agent performed formatting:
1. Did the agent create a 1x1 table (a 'Black Box Warning') containing the EMBRYO-FETAL TOXICITY text?
2. Did the agent create bulleted lists for the stakeholder requirements?
3. Did the agent create a 2-column table for the assessment timetable?

Return JSON format exactly like this:
{
    "black_box_table_visible": true/false,
    "bulleted_lists_visible": true/false,
    "timetable_visible": true/false,
    "meaningful_progression": true/false
}"""
                    result = query_vlm(prompt=prompt, images=images)
                    if result and result.get("success") and result.get("parsed"):
                        parsed = result.get("parsed", {})
                        if parsed.get("black_box_table_visible"): vlm_score += 4
                        if parsed.get("bulleted_lists_visible"): vlm_score += 3
                        if parsed.get("timetable_visible"): vlm_score += 3
                        feedback_parts.append(f"VLM Visual: {vlm_score}/10 pts")
                    else:
                        feedback_parts.append("VLM Visual: failed to parse (0/10)")
                else:
                    feedback_parts.append("VLM Visual: no images (0/10)")
            except Exception as e:
                logger.warning(f"VLM Exception: {e}")
                feedback_parts.append("VLM Visual: error (0/10)")
        else:
            feedback_parts.append("VLM Visual: query_vlm unavailable (0/10)")
        
        score += vlm_score

        # Determine pass/fail
        # Must have the black box warning and heading hierarchy (as key requirements)
        key_criteria_met = bb_warning_found and (h1_score + h2_score >= 10)
        passed = (score >= 70) and key_criteria_met

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Error during verification: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification encountered an error: {e}"
        }
    finally:
        cleanup_verification_temp(temp_dir)