#!/usr/bin/env python3
"""Verifier for the ttrpg_adventure_module_formatting task."""

import logging
import os
import re
import sys
import json
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calligra_verification_utils import (
    check_heading_styles_odt,
    check_paragraph_alignment_odt,
    check_text_bold_odt,
    check_text_font_size_odt,
    copy_and_parse_document,
    get_document_text_odt,
    get_odt_paragraphs,
    get_odt_styles,
    get_odt_tables,
)
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ttrpg_adventure_formatting(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    query_vlm = env_info.get("query_vlm")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    document_path = metadata.get("document_path", "/home/ga/Documents/ashen_king_module.odt")

    # Read exported JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    file_modified = False
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
        file_modified = result.get("file_modified_during_task", False)
    except Exception as e:
        logger.warning(f"Could not read task_result.json: {e}")
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    temp_dir, doc_obj, doc_type = copy_and_parse_document(copy_from_env, document_path)
    if temp_dir is None or doc_type != "odt":
        return {"passed": False, "score": 0, "feedback": "Failed to copy or parse ODT document"}

    content_tree, styles_tree = doc_obj

    score = 0
    feedback_parts = []

    try:
        full_text = get_document_text_odt(content_tree)
        paragraphs = get_odt_paragraphs(content_tree)
        styles = get_odt_styles(content_tree, styles_tree)

        # ----------------------------------------------------------------
        # 1. Title Formatting (Bold, Centered, >=18pt) - 10 pts
        # ----------------------------------------------------------------
        title_text = metadata.get("title_text", "The Crypt of the Ashen King")
        title_pattern = re.escape(title_text)
        
        title_bold = check_text_bold_odt(content_tree, styles_tree, title_pattern)
        title_sized = check_text_font_size_odt(content_tree, styles_tree, title_pattern, 18.0)
        title_centered, _ = check_paragraph_alignment_odt(content_tree, styles_tree, title_pattern, "center")
        
        title_pts = 0
        if title_bold: title_pts += 3
        if title_sized: title_pts += 3
        if title_centered > 0: title_pts += 4
        
        score += title_pts
        if title_pts == 10:
            feedback_parts.append("Title formatted correctly")
        else:
            feedback_parts.append(f"Title formatting incomplete ({title_pts}/10 pts)")

        # ----------------------------------------------------------------
        # 2. Heading Hierarchy (H1, H2, H3) - 20 pts
        # ----------------------------------------------------------------
        expected_h1 = metadata.get("expected_h1", [])
        expected_h2 = metadata.get("expected_h2", [])
        expected_h3 = metadata.get("expected_h3", [])

        h1_matched, h1_tot, _ = check_heading_styles_odt(content_tree, styles_tree, expected_h1, 1)
        h2_matched, h2_tot, _ = check_heading_styles_odt(content_tree, styles_tree, expected_h2, 2)
        h3_matched, h3_tot, _ = check_heading_styles_odt(content_tree, styles_tree, expected_h3, 3)

        tot_headings = h1_tot + h2_tot + h3_tot
        matched_headings = h1_matched + h2_matched + h3_matched
        heading_ratio = matched_headings / max(1, tot_headings)
        
        h_pts = int(20 * heading_ratio)
        score += h_pts
        feedback_parts.append(f"Headings: {matched_headings}/{tot_headings} correct ({h_pts}/20 pts)")

        # ----------------------------------------------------------------
        # 3. Read-Aloud Tag Cleanup - 10 pts
        # ----------------------------------------------------------------
        tags_to_remove = metadata.get("tags_to_remove", [])
        tags_found = 0
        for tag in tags_to_remove:
            # Need to do case-insensitive check and exact match logic
            if tag.lower() in full_text.lower():
                tags_found += 1
                
        if tags_found == 0:
            score += 10
            feedback_parts.append("Placeholder tags removed correctly (10/10 pts)")
        else:
            feedback_parts.append(f"Tags remaining in document: {tags_found} found (0/10 pts)")

        # ----------------------------------------------------------------
        # 4. Read-Aloud Styling (Italic + Indent) - 15 pts
        # ----------------------------------------------------------------
        read_aloud_samples = metadata.get("read_aloud_samples", [])
        styling_matches = 0
        
        for sample in read_aloud_samples:
            sample_lower = sample.lower()
            for para in paragraphs:
                if sample_lower in para['text'].lower():
                    # We found the paragraph. Let's check its style.
                    style_name = para.get('style_name', '')
                    style_props = styles.get(style_name, {})
                    parent_props = styles.get(style_props.get('parent', ''), {})
                    
                    # Check italic (could be in paragraph style or applied text span, but usually paragraph for a block)
                    is_italic = style_props.get('italic', False) or parent_props.get('italic', False)
                    
                    # Check margin-left (indentation)
                    margin_left = style_props.get('margin_left', '') or parent_props.get('margin_left', '')
                    has_indent = False
                    if margin_left and margin_left not in ['0cm', '0in', '0mm', '0pt', '0']:
                        has_indent = True
                    
                    # Also check if italic is applied via a span spanning most of the text
                    if not is_italic:
                        italic_count = check_text_italic_odt(content_tree, styles_tree, re.escape(sample))
                        if italic_count:
                            is_italic = True

                    if is_italic and has_indent:
                        styling_matches += 1
                    elif is_italic or has_indent:
                        styling_matches += 0.5
                    break
        
        rs_ratio = styling_matches / max(1, len(read_aloud_samples))
        rs_pts = int(15 * rs_ratio)
        score += rs_pts
        feedback_parts.append(f"Read-aloud styling: {styling_matches}/{len(read_aloud_samples)} ({rs_pts}/15 pts)")

        # ----------------------------------------------------------------
        # 5. Stat Block Bolding - 15 pts
        # ----------------------------------------------------------------
        stat_labels = metadata.get("stat_block_labels", [])
        bold_matches = 0
        
        for label in stat_labels:
            is_bold = check_text_bold_odt(content_tree, styles_tree, re.escape(label))
            if is_bold:
                bold_matches += 1
                
        sb_ratio = bold_matches / max(1, len(stat_labels))
        sb_pts = int(15 * sb_ratio)
        score += sb_pts
        feedback_parts.append(f"Stat block bolding: {bold_matches}/{len(stat_labels)} ({sb_pts}/15 pts)")

        # ----------------------------------------------------------------
        # 6. Encounter Table Creation - 20 pts
        # ----------------------------------------------------------------
        tables = get_odt_tables(content_tree)
        target_cols = metadata.get("table_columns", 4)
        table_keywords = metadata.get("table_keywords", [])
        
        table_found = False
        table_score = 0
        for tbl in tables:
            # Check if we have roughly 4 columns in any row
            has_cols = any(len(row) == target_cols for row in tbl.get("rows", []))
            
            # Combine all text to search for keywords
            tbl_text = ""
            for row in tbl.get("rows", []):
                tbl_text += " ".join(row).lower() + " "
                
            kw_hits = sum(1 for kw in table_keywords if kw.lower() in tbl_text)
            
            if has_cols and kw_hits >= 2:
                table_found = True
                table_score = 20
                break
            elif has_cols or kw_hits >= 2:
                # Partial credit if they made a table but didn't parse properly
                table_score = max(table_score, 10)
                
        score += table_score
        feedback_parts.append(f"Encounter Table: {'Found' if table_found else 'Incomplete'} ({table_score}/20 pts)")

        # ----------------------------------------------------------------
        # 7. Content Preservation - 10 pts
        # ----------------------------------------------------------------
        # Just ensure they didn't delete the whole document (word count > 200)
        word_count = len(full_text.split())
        if word_count > 200:
            score += 10
            feedback_parts.append("Content preserved (10/10 pts)")
        else:
            feedback_parts.append("Content significantly deleted (0/10 pts)")

        # ----------------------------------------------------------------
        # VLM Trajectory Verification
        # ----------------------------------------------------------------
        vlm_feedback = ""
        if query_vlm:
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            
            prompt = """Analyze this sequence of screenshots of a user formatting a document in Calligra Words.
The user was asked to format a tabletop RPG adventure module (adding headings, italics, tables, and adjusting margins).

Did the user actively interact with the formatting menus, paragraph tools, or table insertion tools? 
Look for evidence of the user highlighting text, opening the Table dialog, adjusting paragraph indent margins, or using the styles panel.

Respond with a JSON object:
{"interacted_with_formatting_tools": true/false, "explanation": "brief reason"}
"""
            try:
                vlm_result = query_vlm(prompt=prompt, images=frames + [final_frame])
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    if parsed.get("interacted_with_formatting_tools"):
                        vlm_feedback = "VLM: Tool interaction confirmed."
                    else:
                        vlm_feedback = "VLM: Minimal or no tool interaction observed."
            except Exception as e:
                logger.warning(f"VLM verification failed: {e}")

        if vlm_feedback:
            feedback_parts.append(vlm_feedback)
            
        # ----------------------------------------------------------------
        # Final Scoring
        # ----------------------------------------------------------------
        if not file_modified:
            score = 0
            feedback_parts.insert(0, "FAIL: Document was not modified during the task.")

        passed = (score >= 75) and (table_score > 0) and (rs_pts > 0)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification script error: {str(e)}"}