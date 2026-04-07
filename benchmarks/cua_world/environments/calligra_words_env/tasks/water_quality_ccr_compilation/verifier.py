#!/usr/bin/env python3
"""Verifier stub for the water_quality_ccr_compilation task.

Full programmatic scoring is deferred to VLM checklist verification.
This stub performs basic anti-gaming and file-existence checks only.
"""

import json
import logging
import os
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calligra_verification_utils import (
    copy_and_parse_document,
    get_document_text_odt,
    get_odt_tables,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_water_quality_ccr_compilation(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    expected_output_path = metadata.get("expected_output_path",
                                        "/home/ga/Desktop/millbrook_ccr_2025.odt")

    # --- Read exported result JSON ---
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

    # --- Gate: output file must exist ---
    if not result.get("output_exists", False):
        return {"passed": False, "score": 0,
                "feedback": f"Output document {expected_output_path} not found"}

    # --- Gate: anti-gaming - file must be created/modified during task ---
    if result.get("output_mtime", 0) < result.get("task_start_time", 0):
        return {"passed": False, "score": 0,
                "feedback": "Document was not created/modified during the task"}

    # --- Basic content check ---
    try:
        temp_dir, doc_obj, doc_type = copy_and_parse_document(
            copy_from_env, expected_output_path)
    except Exception as e:
        return {"passed": False, "score": 5,
                "feedback": f"File exists but failed to parse: {e}"}

    if temp_dir is None or doc_type != "odt":
        return {"passed": False, "score": 5,
                "feedback": "Failed to copy or parse output document as ODF"}

    content_tree, styles_tree = doc_obj
    full_text = get_document_text_odt(content_tree).lower()

    score = 0
    feedback_parts = []

    # Check for content from narrative source
    narrative_kws = metadata.get("content_keywords_narrative", [])
    narrative_hits = sum(1 for kw in narrative_kws if kw.lower() in full_text)
    if narrative_hits >= 2:
        score += 15
        feedback_parts.append(f"Narrative content present ({narrative_hits}/{len(narrative_kws)})")
    else:
        feedback_parts.append(f"Narrative content missing ({narrative_hits}/{len(narrative_kws)})")

    # Check for content from lab results source
    lab_kws = metadata.get("content_keywords_lab", [])
    lab_hits = sum(1 for kw in lab_kws if kw.lower() in full_text)
    if lab_hits >= 2:
        score += 15
        feedback_parts.append(f"Lab data content present ({lab_hits}/{len(lab_kws)})")
    else:
        feedback_parts.append(f"Lab data content missing ({lab_hits}/{len(lab_kws)})")

    # Check for table presence
    tables = get_odt_tables(content_tree)
    if len(tables) >= 1:
        score += 20
        feedback_parts.append(f"Table(s) found: {len(tables)}")
    else:
        feedback_parts.append("No tables found")

    # Check that [REMOVE] notes were deleted
    remove_count = full_text.count("[remove")
    if remove_count == 0:
        score += 15
        feedback_parts.append("All [REMOVE] notes deleted")
    else:
        feedback_parts.append(f"[REMOVE] notes still present: {remove_count}")

    # Stub score for structure (heading styles, TOC, cover page, footer, margins)
    # These will be verified by VLM checklist instead
    score += 10  # baseline for having a parseable document with content
    feedback_parts.append("Structural checks deferred to VLM")

    passed = score >= 60 and narrative_hits >= 2 and lab_hits >= 2
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
