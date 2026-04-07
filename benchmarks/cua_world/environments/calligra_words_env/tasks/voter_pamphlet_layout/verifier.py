#!/usr/bin/env python3
"""Verifier for the voter_pamphlet_layout task."""

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
    cleanup_verification_temp,
    copy_and_parse_document,
    detect_toc_odt,
    ODF_NS
)
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def extract_page_layout_properties(styles_tree):
    """Parse page layout properties to determine landscape and column count."""
    is_landscape = False
    columns = 1

    if styles_tree is None:
        return is_landscape, columns

    for pl in styles_tree.findall('.//style:page-layout-properties', ODF_NS):
        # Check Orientation
        orient = pl.get(f"{{{ODF_NS['style']}}}print-orientation")
        width = pl.get(f"{{{ODF_NS['fo']}}}page-width", "")
        height = pl.get(f"{{{ODF_NS['fo']}}}page-height", "")

        if orient == 'landscape':
            is_landscape = True
        elif width and height:
            try:
                w = float(''.join(c for c in width if c.isdigit() or c == '.'))
                h = float(''.join(c for c in height if c.isdigit() or c == '.'))
                if w > h:
                    is_landscape = True
            except ValueError:
                pass

        # Check Columns
        cols_element = pl.find(f"{{{ODF_NS['style']}}}columns", ODF_NS)
        if cols_element is not None:
            count = cols_element.get(f"{{{ODF_NS['fo']}}}column-count")
            if count and count.isdigit():
                columns = max(columns, int(count))

    return is_landscape, columns


def verify_voter_pamphlet_layout(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    document_path = metadata.get("document_path", "/home/ga/Documents/voter_pamphlet.odt")

    # Retrieve execution metadata (file modifications)
    file_modified = False
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
            file_modified = result_data.get("file_modified_during_task", False)
    except Exception:
        pass
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    temp_dir, doc_obj, doc_type = copy_and_parse_document(copy_from_env, document_path)
    if temp_dir is None or doc_type != "odt":
        return {"passed": False, "score": 0, "feedback": "Failed to copy or parse ODT document"}

    content_tree, styles_tree = doc_obj

    try:
        score = 0
        feedback_parts = []

        # ── 1. Page Layout: Landscape (15 pts) and Columns (15 pts) ──
        is_landscape, columns = extract_page_layout_properties(styles_tree)
        
        if is_landscape:
            score += 15
            feedback_parts.append("Page Layout: Landscape OK")
        else:
            feedback_parts.append("Page Layout: Not Landscape")

        if columns >= 2:
            score += 15
            feedback_parts.append(f"Page Layout: {columns} columns OK")
        else:
            feedback_parts.append("Page Layout: Single column (needs 2)")

        # ── 2. Title Formatting (10 pts) ──
        main_title = metadata.get("main_title", "2026 Official Voter Information Pamphlet")
        title_bold = check_text_bold_odt(content_tree, styles_tree, re.escape(main_title))
        title_centered, _ = check_paragraph_alignment_odt(content_tree, styles_tree, re.escape(main_title), "center")
        title_size = check_text_font_size_odt(content_tree, styles_tree, re.escape(main_title), 16.0)

        if title_bold and title_centered > 0 and title_size:
            score += 10
            feedback_parts.append("Title formatting OK")
        else:
            issues = []
            if not title_bold: issues.append("not bold")
            if title_centered == 0: issues.append("not centered")
            if not title_size: issues.append("size < 16pt")
            feedback_parts.append(f"Title issues: {', '.join(issues)}")

        # ── 3. Table of Contents (10 pts) ──
        if detect_toc_odt(content_tree):
            score += 10
            feedback_parts.append("TOC present")
        else:
            feedback_parts.append("TOC missing")

        # ── 4. Heading Hierarchy (20 pts) ──
        measure_headings = metadata.get("measure_headings", [])
        h1_matched, h1_total, _ = check_heading_styles_odt(content_tree, styles_tree, measure_headings, 1)
        
        # Multiply section headers (3) by measures (3) = 9
        section_headings = metadata.get("section_headings", [])
        h2_matched, h2_total, _ = check_heading_styles_odt(content_tree, styles_tree, section_headings, 2)
        
        if h1_matched >= 3 and h2_matched >= 8:
            score += 20
            feedback_parts.append("Heading hierarchy OK")
        else:
            feedback_parts.append(f"Headings incomplete: H1 ({h1_matched}/3), H2 ({h2_matched}/9)")

        # ── 5. Signature Alignment (15 pts) ──
        signatures = metadata.get("signature_samples", [])
        aligned_sigs = 0
        for sig in signatures:
            # Check for right or end alignment
            r_matched, _ = check_paragraph_alignment_odt(content_tree, styles_tree, re.escape(sig), "right")
            e_matched, _ = check_paragraph_alignment_odt(content_tree, styles_tree, re.escape(sig), "end")
            if r_matched > 0 or e_matched > 0:
                aligned_sigs += 1
                
        if aligned_sigs >= 4:
            score += 15
            feedback_parts.append(f"Signatures right-aligned: {aligned_sigs}/{len(signatures)} OK")
        else:
            feedback_parts.append(f"Signatures right-aligned: {aligned_sigs}/{len(signatures)} (need 4)")

        # ── 6. Body Justification (15 pts) ──
        body_samples = metadata.get("body_samples", [])
        justified_body = 0
        for sample in body_samples:
            matched, _ = check_paragraph_alignment_odt(content_tree, styles_tree, re.escape(sample), "justify")
            if matched > 0:
                justified_body += 1
                
        if justified_body >= 6:
            score += 15
            feedback_parts.append(f"Body text justified: {justified_body}/{len(body_samples)} OK")
        else:
            feedback_parts.append(f"Body text justified: {justified_body}/{len(body_samples)} (need 6)")

        # ── Anti-Gaming Check: Was file actually modified? ──
        if not file_modified:
            score = 0
            feedback_parts.append("CRITICAL: Document was not saved/modified during task execution.")

        # VLM Trajectory Verification as supplementary confidence check
        # Looks for evidence of opening formatting/columns dialogs
        query_vlm = env_info.get("query_vlm")
        if query_vlm and file_modified:
            frames = sample_trajectory_frames(traj, n=5)
            final = get_final_screenshot(traj)
            if frames and final:
                prompt = """Analyze this trajectory of a user formatting a document in a word processor.
                Look for evidence of the following layout modifications:
                1. Did they open Page Setup / Layout menus?
                2. Are there visible columns in the document at any point?
                3. Does the document appear wider (landscape) towards the end?
                
                Respond in JSON format: {"layout_modified": true/false}"""
                
                try:
                    vlm_res = query_vlm(prompt=prompt, images=frames + [final])
                    if vlm_res.get("success"):
                        parsed = vlm_res.get("parsed", {})
                        if parsed.get("layout_modified"):
                            feedback_parts.append("VLM confirms layout interaction")
                        else:
                            feedback_parts.append("VLM warning: layout interaction not clearly observed")
                except Exception as e:
                    logger.warning(f"VLM verification error: {e}")

        # Final Evaluation
        passed = score >= 75 and is_landscape and columns >= 2 and file_modified
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    finally:
        cleanup_verification_temp(temp_dir)