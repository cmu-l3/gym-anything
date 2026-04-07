#!/usr/bin/env python3
"""Verifier for the zoning_ordinance_legislative_markup task."""

import logging
import os
import re
import sys
import xml.etree.ElementTree as ET

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calligra_verification_utils import (
    copy_and_parse_document,
    get_document_text_odt,
    get_odt_paragraphs,
    get_odt_styles,
    ODF_NS
)

from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_length(length_str):
    """Converts a length string (e.g., '0.5in', '1.27cm') to inches."""
    if not length_str:
        return 0.0
    try:
        if length_str.endswith('in'): return float(length_str[:-2])
        if length_str.endswith('cm'): return float(length_str[:-2]) / 2.54
        if length_str.endswith('mm'): return float(length_str[:-2]) / 25.4
        if length_str.endswith('pt'): return float(length_str[:-2]) / 72.0
        return float(length_str)
    except Exception:
        return 0.0


def check_inline_style_applied(content_tree, styles_tree, target_text, style_attr):
    """
    Checks if a target phrase is enclosed in a span that has a specific style attribute.
    e.g. style_attr="style:text-underline-style" or "style:text-line-through-style"
    """
    # 1. Map automatic styles to whether they contain the property
    valid_styles = set()
    for tree in [content_tree, styles_tree]:
        if tree is None: continue
        auto_styles = tree.find('.//office:automatic-styles', ODF_NS)
        if auto_styles is not None:
            for style in auto_styles:
                name = style.get(f"{{{ODF_NS['style']}}}name")
                text_props = style.find(f"{{{ODF_NS['style']}}}text-properties")
                if text_props is not None:
                    # Look for the exact attribute
                    val = text_props.get(f"{{{ODF_NS['style']}}}{style_attr.split(':')[-1]}")
                    if val and val.lower() not in ('none', 'false', '', '0'):
                        valid_styles.add(name)

    # 2. Search paragraphs for spans wrapping the target text
    for para in content_tree.findall('.//text:p', ODF_NS):
        for span in para.findall('.//text:span', ODF_NS):
            text = "".join(span.itertext())
            if target_text.lower() in text.lower():
                style_name = span.get(f"{{{ODF_NS['text']}}}style-name")
                if style_name in valid_styles:
                    return True
    return False


def verify_zoning_ordinance_markup(traj, env_info, task_info):
    """Verifies the ordinance legislative markup and formatting."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    document_path = metadata.get("document_path", "/home/ga/Documents/draft_adu_ordinance.odt")

    # 1. Fetch and Parse ODT Document
    temp_dir, doc_obj, doc_type = copy_and_parse_document(copy_from_env, document_path)
    if temp_dir is None or doc_type != "odt":
        return {"passed": False, "score": 0, "feedback": "Failed to copy or parse ODT document"}

    content_tree, styles_tree = doc_obj

    try:
        score = 0
        feedback_parts = []
        
        full_text = get_document_text_odt(content_tree)
        paragraphs = get_odt_paragraphs(content_tree)
        styles = get_odt_styles(content_tree, styles_tree)

        # ── Criterion 1: Marker Cleanup (10 points) ──
        # Check if ++ and -- were successfully removed
        marker_count = full_text.count("++") + full_text.count("--")
        if marker_count == 0:
            score += 10
            feedback_parts.append("Marker Cleanup: OK")
            marker_cleanup_ok = True
        else:
            feedback_parts.append(f"Marker Cleanup: Failed ({marker_count} markers remain)")
            marker_cleanup_ok = False

        # ── Criterion 2: Additions Underlined (20 points, 4 points each) ──
        additions = metadata.get("additions", [])
        additions_matched = 0
        for text in additions:
            if check_inline_style_applied(content_tree, styles_tree, text, "style:text-underline-style"):
                additions_matched += 1
        
        score += (additions_matched * 4)
        feedback_parts.append(f"Additions Underlined: {additions_matched}/{len(additions)}")

        # ── Criterion 3: Deletions Struck Through (20 points, 4 points each) ──
        deletions = metadata.get("deletions", [])
        deletions_matched = 0
        for text in deletions:
            if check_inline_style_applied(content_tree, styles_tree, text, "style:text-line-through-style"):
                deletions_matched += 1
        
        score += (deletions_matched * 4)
        feedback_parts.append(f"Deletions Struck Through: {deletions_matched}/{len(deletions)}")

        # ── Criterion 4: Header Formatting (10 points) ──
        # Bold and Centered top lines
        header_phrases = metadata.get("header_phrases", [])
        header_ok_count = 0
        for phrase in header_phrases:
            for para in paragraphs:
                if phrase.lower() in para['text'].lower():
                    style_info = styles.get(para.get('style_name', ''), {})
                    is_centered = style_info.get('alignment') in ['center']
                    # Look for bold in style info or child spans
                    is_bold = style_info.get('bold', False)
                    if not is_bold:
                        # Check child spans
                        if check_inline_style_applied(content_tree, styles_tree, phrase, "style:font-weight"):
                            is_bold = True # Rough fallback
                            
                    if is_centered:
                        header_ok_count += 1
                    break
        
        if header_ok_count >= len(header_phrases):
            score += 10
            feedback_parts.append("Header Formatting: OK")
        else:
            score += 5 if header_ok_count > 0 else 0
            feedback_parts.append(f"Header Formatting: {header_ok_count}/{len(header_phrases)}")

        # ── Criterion 5: Preamble Spacing (15 points) ──
        preamble_count = 0
        preamble_spaced = 0
        for para in paragraphs:
            if para['text'].startswith("WHEREAS"):
                preamble_count += 1
                style_info = styles.get(para.get('style_name', ''), {})
                line_height = style_info.get('line_height', '')
                margin_bottom = parse_length(style_info.get('margin_bottom', ''))
                
                if line_height.endswith('%') and float(line_height[:-1]) >= 110:
                    preamble_spaced += 1
                elif margin_bottom >= 0.1:  # Accept bottom margin as an alternative spacing strategy
                    preamble_spaced += 1
                else:
                    # Also check raw paragraph style for fo:line-height or style:line-spacing
                    raw_style = None
                    for tree in [content_tree, styles_tree]:
                        if tree is None: continue
                        auto_styles = tree.find('.//office:automatic-styles', ODF_NS)
                        if auto_styles is not None:
                            for style in auto_styles:
                                if style.get(f"{{{ODF_NS['style']}}}name") == para.get('style_name', ''):
                                    para_props = style.find(f"{{{ODF_NS['style']}}}paragraph-properties")
                                    if para_props is not None:
                                        ls = para_props.get(f"{{{ODF_NS['style']}}}line-spacing")
                                        if ls: 
                                            preamble_spaced += 1
                                            break
        if preamble_count > 0 and preamble_spaced >= (preamble_count - 1):
            score += 15
            feedback_parts.append("Preamble Spacing: OK")
        else:
            feedback_parts.append(f"Preamble Spacing: {preamble_spaced}/{preamble_count} spaced")

        # ── Criterion 6: Code Block Indentation (15 points) ──
        code_phrases = metadata.get("code_indent_phrases", [])
        code_indented = 0
        for phrase in code_phrases:
            for para in paragraphs:
                if para['text'].startswith(phrase):
                    style_info = styles.get(para.get('style_name', ''), {})
                    left_margin = parse_length(style_info.get('margin_left', '0in'))
                    if left_margin >= 0.35: # Giving a little tolerance to the 0.5in
                        code_indented += 1
                    break
        
        if code_indented >= len(code_phrases) - 1:
            score += 15
            feedback_parts.append("Code Indentation: OK")
        else:
            feedback_parts.append(f"Code Indentation: {code_indented}/{len(code_phrases)}")

        # ── Criterion 7: Signature Alignment (10 points) ──
        signature_phrases = metadata.get("signature_phrases", [])
        sig_aligned = 0
        for phrase in signature_phrases:
            for para in paragraphs:
                if phrase.lower() in para['text'].lower():
                    style_info = styles.get(para.get('style_name', ''), {})
                    if style_info.get('alignment') in ['end', 'right']:
                        sig_aligned += 1
                    break
                    
        if sig_aligned == len(signature_phrases):
            score += 10
            feedback_parts.append("Signature Alignment: OK")
        else:
            feedback_parts.append(f"Signature Alignment: {sig_aligned}/{len(signature_phrases)}")

        # ── Anti-Gaming: VLM Trajectory Verification ──
        query_vlm = env_info.get("query_vlm")
        vlm_passed = True
        if query_vlm:
            frames = sample_trajectory_frames(traj, n=4)
            if frames:
                prompt = (
                    "You are analyzing screenshots of a word processor (Calligra Words) task. "
                    "Did the user use the application's graphical UI to interact with the text? "
                    "Look for evidence like text being highlighted, formatting panels open, "
                    "mouse cursor interacting with menus, or properties dock changes. "
                    "Respond with JSON: {'gui_used': true/false}"
                )
                try:
                    result = query_vlm(images=frames, prompt=prompt)
                    if result and result.get("success"):
                        parsed = result.get("parsed", {})
                        if not parsed.get("gui_used", True):
                            logger.warning("VLM detected lack of GUI usage.")
                            vlm_passed = False
                            feedback_parts.append("VLM: No evidence of GUI usage (scripting suspected)")
                except Exception as e:
                    logger.error(f"VLM verification error: {e}")

        # Final Evaluation
        passed = (
            score >= 70 and
            marker_cleanup_ok and
            additions_matched >= 3 and
            deletions_matched >= 3 and
            vlm_passed
        )

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {str(e)}")
        return {"passed": False, "score": 0, "feedback": f"Verification failed with error: {str(e)}"}
    finally:
        # Cleanup temp files
        if 'temp_dir' in locals() and temp_dir and os.path.exists(temp_dir):
            import shutil
            shutil.rmtree(temp_dir, ignore_errors=True)