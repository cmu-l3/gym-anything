#!/usr/bin/env python3
"""Verifier for create_print_layout_export_pdf task."""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_create_print_layout_export_pdf(traj, env_info, task_info):
    """
    Verify that a print layout was created and exported as PDF.

    Scoring (100 points):
    - PDF file exists at expected path: 20 points
    - PDF is valid format (starts with %PDF): 10 points
    - PDF has substantial content (>50KB, not blank): 25 points
    - PDF has at least 1 page: 10 points
    - PDF size indicates map elements rendered (>100KB): 20 points
    - New PDF file created (not pre-existing): 15 points

    Pass threshold: 55 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    logger.info(f"Task result: {result}")

    score = 0
    feedback_parts = []
    subscores = {}

    # Criterion 1: PDF exists at expected path (20 pts)
    pdf_exists = result.get('pdf_exists', False)
    if pdf_exists:
        score += 20
        subscores["pdf_exists"] = True
        feedback_parts.append("PDF file found")
    else:
        subscores["pdf_exists"] = False
        feedback_parts.append("PDF file NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Valid PDF format (10 pts)
    if result.get('pdf_valid', False):
        score += 10
        subscores["pdf_valid"] = True
        feedback_parts.append("Valid PDF format")
    else:
        subscores["pdf_valid"] = False
        feedback_parts.append("Invalid PDF format")

    # Criterion 3: Substantial content (25 pts)
    pdf_size = result.get('pdf_size_bytes', 0)
    if result.get('pdf_has_content', False):
        score += 25
        subscores["has_content"] = True
        feedback_parts.append(f"PDF has substantial content ({pdf_size} bytes)")
    elif pdf_size > 10000:
        score += 12
        subscores["has_content"] = False
        feedback_parts.append(f"PDF has some content ({pdf_size} bytes)")
    else:
        subscores["has_content"] = False
        feedback_parts.append(f"PDF appears empty or minimal ({pdf_size} bytes)")

    # Criterion 4: Has at least 1 page (10 pts)
    page_count = result.get('pdf_page_count', 0)
    if page_count >= 1:
        score += 10
        subscores["has_pages"] = True
        feedback_parts.append(f"PDF has {page_count} page(s)")
    else:
        subscores["has_pages"] = False
        feedback_parts.append("Could not detect pages in PDF")

    # Criterion 5: Size indicates full map layout with elements (20 pts)
    # A properly rendered map layout with title, legend, scale bar, north arrow
    # typically produces a PDF > 100KB
    if pdf_size > 100000:
        score += 20
        subscores["full_layout"] = True
        feedback_parts.append("PDF size suggests complete layout with elements")
    elif pdf_size > 50000:
        score += 10
        subscores["full_layout"] = False
        feedback_parts.append("PDF size suggests partial layout")
    else:
        subscores["full_layout"] = False
        feedback_parts.append("PDF too small for complete layout")

    # Criterion 6: New file created (15 pts)
    initial = result.get('initial_pdf_count', 0)
    current = result.get('current_pdf_count', 0)
    if current > initial:
        score += 15
        subscores["new_file"] = True
        feedback_parts.append("New PDF created")
    else:
        subscores["new_file"] = False
        feedback_parts.append("No new PDF files detected")

    passed = score >= 55 and subscores.get("pdf_exists", False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }
