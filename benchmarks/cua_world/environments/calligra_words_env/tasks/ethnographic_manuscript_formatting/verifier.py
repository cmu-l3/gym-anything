#!/usr/bin/env python3
"""Verifier for the ethnographic_manuscript_formatting task."""

import logging
import os
import re
import sys

# Ensure utils can be imported
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calligra_verification_utils import (
    check_heading_styles_odt,
    check_paragraph_alignment_odt,
    copy_and_parse_document,
    get_document_text_odt,
    get_odt_paragraphs,
    get_odt_styles,
    get_odt_tables,
    vlm_verify_screenshot,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_length(length_str):
    """Parse ODF length string (e.g., '1.27cm', '0.5in') into inches."""
    if not length_str:
        return 0.0
    try:
        match = re.search(r"([-+]?\d*\.\d+|\d+)", str(length_str))
        if not match:
            return 0.0
        val = float(match.group(1))
        if "cm" in length_str:
            return val * 0.393701
        if "mm" in length_str:
            return val * 0.0393701
        if "in" in length_str:
            return val
        if "pt" in length_str:
            return val / 72.0
        return val
    except Exception:
        return 0.0

def _resolve_style_property(styles, style_name, property_key):
    """Walk up the style hierarchy to find a specific property."""
    current = style_name
    visited = set()
    while current and current not in visited:
        visited.add(current)
        style_info = styles.get(current, {})
        if property_key in style_info and style_info[property_key]:
            return style_info[property_key]
        current = style_info.get("parent", "")
    return ""

def verify_ethnographic_manuscript_formatting(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    document_path = metadata.get("document_path", "/home/ga/Documents/coastal_harvest_manuscript.odt")

    temp_dir, doc_obj, doc_type = copy_and_parse_document(copy_from_env, document_path)
    if temp_dir is None or doc_type != "odt":
        return {"passed": False, "score": 0, "feedback": "Failed to copy or parse ODT document"}

    content_tree, styles_tree = doc_obj

    try:
        score = 0
        feedback_parts = []
        
        paragraphs = get_odt_paragraphs(content_tree)
        styles = get_odt_styles(content_tree, styles_tree)
        full_text = get_document_text_odt(content_tree)

        # ----------------------------------------------------------------
        # Criterion 1: Chapter Headings (10 points)
        # ----------------------------------------------------------------
        chapter_headings = metadata.get("chapter_headings", [])
        h1_matched, h1_total, _ = check_heading_styles_odt(content_tree, styles_tree, chapter_headings, 1)
        
        center_matched = 0
        for ch in chapter_headings:
            matched, _ = check_paragraph_alignment_odt(content_tree, styles_tree, re.escape(ch), "center")
            if matched > 0:
                center_matched += 1

        if h1_matched == h1_total and center_matched == h1_total:
            score += 10
            feedback_parts.append("Chapter headings: H1 and Centered OK")
        elif h1_matched >= 2 or center_matched >= 2:
            score += 5
            feedback_parts.append(f"Chapter headings: Partial (H1: {h1_matched}/{h1_total}, Centered: {center_matched}/{h1_total})")
        else:
            feedback_parts.append("Chapter headings: Missing H1 or Center alignment")

        # ----------------------------------------------------------------
        # Criterion 2: Line Spacing (1.5x) (20 points)
        # ODF uses line-height percentages like "150%" or proportional values.
        # We sample body paragraphs.
        # ----------------------------------------------------------------
        body_samples = metadata.get("body_samples", [])
        spacing_ok_count = 0
        
        for sample in body_samples:
            for para in paragraphs:
                if sample.lower() in para['text'].lower():
                    line_height = _resolve_style_property(styles, para['style_name'], "line_height")
                    if "150%" in line_height or "1.5" in line_height:
                        spacing_ok_count += 1
                    break
        
        if len(body_samples) > 0 and spacing_ok_count == len(body_samples):
            score += 20
            feedback_parts.append("Line spacing: 1.5x OK")
        elif spacing_ok_count > 0:
            score += 10
            feedback_parts.append(f"Line spacing: 1.5x applied to {spacing_ok_count}/{len(body_samples)} body samples")
        else:
            feedback_parts.append("Line spacing: 1.5x not detected")

        # ----------------------------------------------------------------
        # Criterion 3: First-line Indents (~0.5 inches) (20 points)
        # ----------------------------------------------------------------
        indent_ok_count = 0
        
        for sample in body_samples:
            for para in paragraphs:
                if sample.lower() in para['text'].lower():
                    text_indent_str = _resolve_style_property(styles, para['style_name'], "text_indent")
                    indent_in = parse_length(text_indent_str)
                    if 0.4 <= indent_in <= 0.6:  # roughly 0.5 inches
                        indent_ok_count += 1
                    break

        if len(body_samples) > 0 and indent_ok_count == len(body_samples):
            score += 20
            feedback_parts.append("First-line indents: ~0.5in OK")
        elif indent_ok_count > 0:
            score += 10
            feedback_parts.append(f"First-line indents: Partial ({indent_ok_count}/{len(body_samples)})")
        else:
            feedback_parts.append("First-line indents: Missing or incorrect size")

        # ----------------------------------------------------------------
        # Criterion 4: Block Quote Margins (Left/Right ~0.5in, 10pt) (20 points)
        # First-line indent must be 0 or missing.
        # ----------------------------------------------------------------
        quote_samples = metadata.get("quote_samples", [])
        bq_margin_ok = 0
        bq_font_ok = 0
        bq_no_indent_ok = 0

        for sample in quote_samples:
            for para in paragraphs:
                if sample.lower() in para['text'].lower():
                    margin_left = parse_length(_resolve_style_property(styles, para['style_name'], "margin_left"))
                    margin_right = parse_length(_resolve_style_property(styles, para['style_name'], "margin_right"))
                    text_indent = parse_length(_resolve_style_property(styles, para['style_name'], "text_indent"))
                    font_size_str = _resolve_style_property(styles, para['style_name'], "font_size")
                    
                    if 0.4 <= margin_left <= 0.6 and 0.4 <= margin_right <= 0.6:
                        bq_margin_ok += 1
                    if text_indent <= 0.05:
                        bq_no_indent_ok += 1
                    if "10" in str(font_size_str):
                        bq_font_ok += 1
                    break

        total_quotes = len(quote_samples)
        if total_quotes > 0 and bq_margin_ok >= total_quotes - 1 and bq_no_indent_ok >= total_quotes - 1:
            score += 20
            feedback_parts.append("Block quote formatting: Margins and zero-indent OK")
        elif bq_margin_ok > 0:
            score += 10
            feedback_parts.append(f"Block quote formatting: Partial margins applied ({bq_margin_ok}/{total_quotes})")
        else:
            feedback_parts.append("Block quote formatting: Missing correct margins")

        if bq_font_ok >= total_quotes - 1:
            feedback_parts.append("Block quote font: 10pt OK")
        else:
            feedback_parts.append(f"Block quote font: only {bq_font_ok}/{total_quotes} are 10pt")

        # ----------------------------------------------------------------
        # Criterion 5: Transcript Cleanup (10 points)
        # ----------------------------------------------------------------
        if "TRANSCRIPT:" not in full_text:
            score += 10
            feedback_parts.append("Transcript tags: Removed OK")
        else:
            feedback_parts.append("Transcript tags: Still present in document")

        # ----------------------------------------------------------------
        # Criterion 6: Table Creation (20 points)
        # ----------------------------------------------------------------
        tables = get_odt_tables(content_tree)
        table_keywords = metadata.get("table_keywords", [])
        
        table_text = ""
        for tbl in tables:
            for row in tbl.get("rows", []):
                table_text += " ".join(row).lower() + " "

        keyword_hits = sum(1 for kw in table_keywords if kw.lower() in table_text)
        
        if len(tables) >= 1 and keyword_hits >= 4:
            score += 20
            feedback_parts.append("Demographic Table: Created successfully")
        elif len(tables) >= 1:
            score += 10
            feedback_parts.append(f"Demographic Table: Created but missing content ({keyword_hits} keywords)")
        else:
            feedback_parts.append("Demographic Table: Missing")

        # VLM trajectory verification as anti-gaming safety
        vlm_passed = False
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=3)
            final_frame = get_final_screenshot(traj)
            
            prompt = (
                "You are reviewing an agent formatting a manuscript in Calligra Words. "
                "Did the agent actively navigate menus, apply styles, or convert text to a table? "
                "Look for evidence of document modifications compared to a raw text file. "
                "Respond with JSON containing boolean 'formatting_observed' and a 'reason' string."
            )
            vlm_res = env_info.get("query_vlm", lambda **kw: None)(
                images=frames + [final_frame] if final_frame else frames,
                prompt=prompt
            )
            if vlm_res and getattr(vlm_res, "success", False):
                try:
                    parsed = vlm_res.parsed if hasattr(vlm_res, "parsed") else json.loads(vlm_res.get("text", "{}"))
                    if parsed.get("formatting_observed", False):
                        vlm_passed = True
                        logger.info(f"VLM verification passed: {parsed.get('reason')}")
                except Exception as e:
                    logger.warning(f"VLM parsing error: {e}")
        except Exception as e:
            logger.warning(f"VLM execution error: {e}")

        if not vlm_passed:
            logger.warning("VLM did not observe clear formatting activity, but continuing with programmatic score.")

        # Determine pass/fail
        passed = (score >= 70) and (indent_ok_count > 0) and (bq_margin_ok > 0)

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification encountered an error: {e}"
        }
    finally:
        cleanup_verification_temp(temp_dir)