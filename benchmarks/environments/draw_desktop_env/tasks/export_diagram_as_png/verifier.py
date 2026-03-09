#!/usr/bin/env python3
"""Verifier for export_diagram_as_png task.
Checks if the hospital ER diagram was exported as a valid PNG image.
"""

import json
import tempfile
import os


def verify_export_diagram_as_png(traj, env_info, task_info):
    """Verify that the diagram was exported as PNG."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_file_size_kb = metadata.get('min_file_size_kb', 5)

    # Copy result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    criteria_met = 0
    total_criteria = 5

    # Criterion 1: Export file exists (20 points)
    if result.get('file_exists'):
        score += 20
        criteria_met += 1
        feedback_parts.append(f"Export file exists: {result.get('file_path')}")
    else:
        feedback_parts.append("FAIL: Export PNG file not found on Desktop")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts)
        }

    # Criterion 2: Valid PNG format (20 points)
    if result.get('is_valid_png'):
        score += 20
        criteria_met += 1
        feedback_parts.append("Valid PNG format")
    else:
        feedback_parts.append("File is NOT valid PNG format")

    # Criterion 3: Reasonable file size (15 points)
    file_size = result.get('file_size', 0)
    file_size_kb = file_size / 1024
    if file_size_kb >= min_file_size_kb:
        score += 15
        criteria_met += 1
        feedback_parts.append(f"File size: {file_size_kb:.1f} KB (min: {min_file_size_kb} KB)")
    elif file_size_kb >= 1:
        score += 7
        feedback_parts.append(f"File small: {file_size_kb:.1f} KB")
    else:
        feedback_parts.append(f"File too small: {file_size} bytes")

    # Criterion 4: Image has reasonable dimensions (20 points)
    width = result.get('image_width', 0)
    height = result.get('image_height', 0)
    if width >= 100 and height >= 100:
        score += 20
        criteria_met += 1
        feedback_parts.append(f"Image dimensions: {width}x{height}")
    elif width > 0 and height > 0:
        score += 10
        feedback_parts.append(f"Image dimensions small: {width}x{height}")
    else:
        feedback_parts.append("Could not determine image dimensions")

    # Criterion 5: PNG contains actual diagram content (25 points)
    # Checks unique color count (blank image has ~1 color, diagram has >20)
    # and optionally embedded draw.io XML in PNG tEXt chunks
    has_diagram_content = result.get('has_diagram_content', False)
    unique_colors = result.get('unique_colors', 0)
    has_embedded_xml = result.get('has_embedded_xml', False)

    if has_diagram_content:
        score += 25
        criteria_met += 1
        detail = f"unique colors: {unique_colors}"
        if has_embedded_xml:
            detail += ", embedded diagram XML"
        feedback_parts.append(f"Diagram content verified ({detail})")
    elif unique_colors > 5:
        # Some content but not enough to be a full diagram
        score += 10
        feedback_parts.append(f"Partial content (unique colors: {unique_colors})")
    else:
        feedback_parts.append(f"No diagram content detected (unique colors: {unique_colors})")

    # Pass requirements:
    # - File must exist and be valid PNG
    # - File must have reasonable size OR diagram content
    # - Score >= 60
    is_valid = result.get('is_valid_png', False)
    has_size = file_size_kb >= min_file_size_kb
    has_dimensions = width >= 100 and height >= 100

    passed = (score >= 60 and
              is_valid and
              (has_size or has_dimensions) and
              (has_diagram_content or unique_colors > 5))

    if passed:
        feedback_parts.append("PNG export successful!")
    else:
        reasons = []
        if not is_valid:
            reasons.append("not a valid PNG")
        if not has_size and not has_dimensions:
            reasons.append(f"file too small ({file_size_kb:.1f} KB)")
        if not has_diagram_content and unique_colors <= 5:
            reasons.append(f"no diagram content (colors: {unique_colors})")
        if score < 60:
            reasons.append(f"score {score} < 60")
        feedback_parts.append(f"FAILED: {'; '.join(reasons)}")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": {
            "file_exists": result.get('file_exists', False),
            "is_valid_png": is_valid,
            "file_size_kb": round(file_size_kb, 1),
            "image_width": width,
            "image_height": height,
            "has_diagram_content": has_diagram_content,
            "unique_colors": unique_colors,
            "has_embedded_xml": has_embedded_xml,
            "criteria_met": criteria_met,
            "total_criteria": total_criteria
        }
    }
