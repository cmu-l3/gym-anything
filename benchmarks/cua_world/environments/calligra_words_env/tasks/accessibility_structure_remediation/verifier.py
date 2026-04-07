#!/usr/bin/env python3
"""Verifier for the accessibility_structure_remediation task."""

import logging
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calligra_verification_utils import (
    check_heading_styles_odt,
    copy_and_parse_document,
    detect_toc_odt,
    get_document_text_odt,
    get_odt_paragraphs,
    get_odt_tables,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_accessibility_structure_remediation(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    output_path = metadata.get("output_path", "/home/ga/Documents/accessible_equity_plan.odt")

    # Check if agent created the file
    temp_dir, doc_obj, doc_type = copy_and_parse_document(copy_from_env, output_path)
    if temp_dir is None or doc_type != "odt":
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to locate or parse {output_path}. Did you save the document correctly?"
        }

    content_tree, styles_tree = doc_obj
    
    score = 0
    feedback_parts = []
    
    # 1. H1 Headings (20 points)
    expected_h1 = metadata.get("expected_h1", ["Executive Summary", "Current Landscape", "Strategic Goals", "Regional Funding Allocation"])
    h1_matched, h1_total, _ = check_heading_styles_odt(content_tree, styles_tree, expected_h1, 1)
    if h1_matched >= 3:
        score += 20
        feedback_parts.append(f"H1 semantics: {h1_matched}/{h1_total} OK")
    else:
        feedback_parts.append(f"H1 semantics: {h1_matched}/{h1_total} (need >= 3)")

    # 2. H2 Headings (15 points)
    expected_h2 = metadata.get("expected_h2", ["Infrastructure Gap", "Digital Literacy"])
    h2_matched, h2_total, _ = check_heading_styles_odt(content_tree, styles_tree, expected_h2, 2)
    if h2_matched >= 2:
        score += 15
        feedback_parts.append(f"H2 semantics: {h2_matched}/{h2_total} OK")
    else:
        feedback_parts.append(f"H2 semantics: {h2_matched}/{h2_total} (need 2)")

    # 3. Semantic List (20 points)
    paragraphs = get_odt_paragraphs(content_tree)
    list_keywords = ["fiber network", "low-cost device", "libraries for community"]
    matched_keywords = set()
    for para in paragraphs:
        if para.get("is_list_item"):
            text = para.get("text", "").lower()
            for kw in list_keywords:
                if kw in text:
                    matched_keywords.add(kw)

    if len(matched_keywords) >= 2:
        score += 20
        feedback_parts.append("Semantic list created OK")
    else:
        feedback_parts.append(f"Semantic list: {len(matched_keywords)}/3 required items found in ODF list elements")

    # 4. Semantic Table (20 points)
    tables = get_odt_tables(content_tree)
    table_keywords = ["unserved", "$45m", "$68m", "north", "south"]
    best_table_hits = 0
    for tbl in tables:
        tbl_text = ""
        for row in tbl.get("rows", []):
            tbl_text += " ".join(row).lower() + " "
        hits = sum(1 for kw in table_keywords if kw in tbl_text)
        if hits > best_table_hits:
            best_table_hits = hits

    if best_table_hits >= 3:
        score += 20
        feedback_parts.append("Semantic table created OK")
    else:
        feedback_parts.append(f"Semantic table: keywords {best_table_hits}/{len(table_keywords)} found in table elements")

    # 5. Table of Contents (15 points)
    has_toc = detect_toc_odt(content_tree)
    if has_toc:
        score += 15
        feedback_parts.append("TOC present OK")
    else:
        feedback_parts.append("TOC missing")

    # 6. Content Preservation (10 points)
    full_text = get_document_text_odt(content_tree).lower()
    content_keywords = metadata.get("content_keywords", [
        "broadband development",
        "digital equity",
        "surveys",
        "15%",
        "18,200",
        "14,100"
    ])
    kw_hits = sum(1 for kw in content_keywords if kw.lower() in full_text)
    if kw_hits >= len(content_keywords) - 1:
        score += 10
        feedback_parts.append("Content preserved OK")
    else:
        feedback_parts.append(f"Content preserved: {kw_hits}/{len(content_keywords)}")

    cleanup_verification_temp(temp_dir)

    # Pass threshold is 75 points, plus hard conditions for creating semantic table and H1
    passed = score >= 75 and h1_matched >= 3 and best_table_hits >= 3

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }