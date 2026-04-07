#!/usr/bin/env python3
"""Verifier for the quarterly_report_consolidation task."""

import logging
import os
import json
import re
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calligra_verification_utils import (
    check_heading_styles_odt,
    check_paragraph_alignment_odt,
    check_text_bold_odt,
    copy_and_parse_document,
    detect_toc_odt,
    get_document_text_odt,
    get_odt_tables,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_quarterly_report_consolidation(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    expected_output_path = metadata.get("expected_output_path", "/home/ga/Documents/quarterly_review_q3.odt")
    
    # Read the JSON result exported from the environment
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 1. Output Existence
    if not result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": f"Output document {expected_output_path} not found"}

    # 2. Anti-gaming check: Make sure file was created/modified during the task
    if result.get("output_mtime", 0) < result.get("task_start_time", 0):
        return {"passed": False, "score": 0, "feedback": "Document was not created/modified during the task. State unchanged."}

    # Fetch and parse the target ODT file
    temp_dir, doc_obj, doc_type = copy_and_parse_document(copy_from_env, expected_output_path)
    if temp_dir is None or doc_type != "odt":
        return {"passed": False, "score": 0, "feedback": "Failed to copy or parse output document"}

    content_tree, styles_tree = doc_obj
    full_text = get_document_text_odt(content_tree).lower()

    score = 0
    feedback_parts = []

    # --- Criterion 1: Content Synthesis (30 points) ---
    sales_kws = [kw.lower() for kw in metadata.get("sales_keywords", [])]
    ops_kws = [kw.lower() for kw in metadata.get("ops_keywords", [])]
    fin_kws = [kw.lower() for kw in metadata.get("finance_keywords", [])]

    s_hits = sum(1 for kw in sales_kws if kw in full_text)
    o_hits = sum(1 for kw in ops_kws if kw in full_text)
    f_hits = sum(1 for kw in fin_kws if kw in full_text)

    if s_hits >= 3:
        score += 10
        feedback_parts.append("Sales content found")
    else:
        feedback_parts.append(f"Sales content missing ({s_hits}/{len(sales_kws)})")

    if o_hits >= 3:
        score += 10
        feedback_parts.append("Ops content found")
    else:
        feedback_parts.append(f"Ops content missing ({o_hits}/{len(ops_kws)})")

    if f_hits >= 3:
        score += 10
        feedback_parts.append("Finance content found")
    else:
        feedback_parts.append(f"Finance content missing ({f_hits}/{len(fin_kws)})")

    # --- Criterion 2: Executive Summary (10 points) ---
    if "executive summary" in full_text:
        score += 10
        feedback_parts.append("Executive summary present")
    else:
        feedback_parts.append("Executive summary missing")

    # --- Criterion 3: Heading Hierarchy (25 points) ---
    expected_h1 = metadata.get("expected_h1", ["Sales", "Operations", "Finance"])
    expected_h2 = metadata.get("expected_h2", [])
    
    h1_matched, _, _ = check_heading_styles_odt(content_tree, styles_tree, expected_h1, 1)
    if h1_matched >= 2:
        score += 15
        feedback_parts.append(f"H1 matched: {h1_matched}/{len(expected_h1)}")
    else:
        feedback_parts.append(f"H1 insufficient: {h1_matched}/{len(expected_h1)}")

    h2_matched, _, _ = check_heading_styles_odt(content_tree, styles_tree, expected_h2, 2)
    if h2_matched >= 5:
        score += 10
        feedback_parts.append(f"H2 matched: {h2_matched}/{len(expected_h2)}")
    else:
        feedback_parts.append(f"H2 insufficient: {h2_matched}/{len(expected_h2)}")

    # --- Criterion 4: Formatting (Body Text Justification) (10 points) ---
    body_samples = [
        "driven by strong enterprise renewals",
        "achieving our annual target early",
        "primarily driven by the memphis facility equipment",
        "pipeline value stands at"
    ]
    justified_count = 0
    for sample in body_samples:
        if sample.lower() in full_text:
            matched, _ = check_paragraph_alignment_odt(
                content_tree, styles_tree, re.escape(sample), "justify", case_sensitive=False
            )
            if matched > 0:
                justified_count += 1

    if justified_count >= 2:
        score += 10
        feedback_parts.append("Body formatting unified (justified)")
    else:
        feedback_parts.append(f"Body text not justified ({justified_count}/{len(body_samples)} samples)")

    # --- Criterion 5: Tables Preserved (10 points) ---
    tables = get_odt_tables(content_tree)
    if len(tables) >= 2:
        score += 10
        feedback_parts.append(f"Tables present ({len(tables)})")
    else:
        feedback_parts.append(f"Missing tables (found {len(tables)}, expected 3)")

    # --- Criterion 6: TOC Present (10 points) ---
    if detect_toc_odt(content_tree) or "table of contents" in full_text:
        score += 10
        feedback_parts.append("TOC present")
    else:
        feedback_parts.append("TOC missing")

    # --- Criterion 7: Title formatting (5 points) ---
    title_text = "Q3 2025 Quarterly Business Review"
    title_bold = check_text_bold_odt(content_tree, styles_tree, re.escape(title_text))
    if title_bold or title_text.lower() in full_text:
        score += 5
        feedback_parts.append("Title formatted")
    else:
        feedback_parts.append("Title not bold/found")

    # Passed requires reaching the threshold AND successfully copying content from all 3 files
    key_criteria_met = (s_hits >= 2) and (o_hits >= 2) and (f_hits >= 2)
    passed = (score >= 65) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }