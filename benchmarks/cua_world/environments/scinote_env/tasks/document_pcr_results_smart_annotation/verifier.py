#!/usr/bin/env python3
"""Verifier for document_pcr_results_smart_annotation task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_document_pcr_results(traj, env_info, task_info):
    """
    Verify that file, table, and smart annotation were added to the task results.
    Relying on direct database queries exported by export_result.sh.
    """

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_file = metadata.get('expected_file', 'gel_electrophoresis.jpg')
    table_values = metadata.get('table_values', ["Mutant A", "18.2", "Positive", "Control", "32.5", "Pass"])
    smart_annotation_keyword = metadata.get('smart_annotation_keyword', 'Taq Polymerase')

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/document_pcr_results.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    task_result_count = int(result.get('task_result_count', 0))
    asset_count = int(result.get('asset_count', 0))
    table_count = int(result.get('table_count', 0))
    text_count = int(result.get('text_count', 0))
    file_uploaded = result.get('file_uploaded', False)
    rich_text = result.get('rich_text', '')
    table_data = result.get('table_data', '')

    # Anti-gaming: Ensure results were created inside the target task
    if task_result_count == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No results were added to the 'PCR Validation' task",
            "subscores": {"file_uploaded": False, "table_created": False, "smart_annotation_used": False}
        }

    # Criterion 1 (25 pts): Gel Image Uploaded
    if file_uploaded:
        score += 25
        feedback_parts.append(f"Image '{expected_file}' uploaded correctly")
    elif asset_count > 0:
        score += 15  # Partial credit if some asset was uploaded but filename missing
        feedback_parts.append("An asset was uploaded, but exact filename mismatch")
    else:
        feedback_parts.append("No image asset uploaded")

    # Criterion 2 (20 pts): Table Structure Created
    if table_count > 0:
        score += 20
        feedback_parts.append("Result table created")
    else:
        feedback_parts.append("No result table created")

    # Criterion 3 (15 pts): Table Data Accurate
    data_matches = 0
    if table_count > 0:
        for val in table_values:
            if val.lower() in table_data.lower():
                data_matches += 1
        
        if data_matches == len(table_values):
            score += 15
            feedback_parts.append("Table data is accurate")
        elif data_matches > 0:
            score += int(15 * (data_matches / len(table_values)))  # Partial credit
            feedback_parts.append(f"Table data partially accurate ({data_matches}/{len(table_values)} expected values found)")
        else:
            feedback_parts.append("Table data does not match expected values")
    else:
        feedback_parts.append("Cannot verify table data (no table created)")

    # Criterion 4 (10 pts): Conclusion Text Added
    if text_count > 0:
        score += 10
        feedback_parts.append("Text note created")
    else:
        feedback_parts.append("No text note created")

    # Criterion 5 (30 pts): Smart Annotation Used
    # A true smart annotation in SciNote generates HTML tags like <action-text-attachment> or data-mention attributes.
    # We check the raw rich text content to ensure it wasn't just typed as plain text.
    smart_annotation_indicators = ["<action-text-attachment", "sgid=", "href=", "data-mention", "repository_row"]
    has_smart_link = False
    
    if text_count > 0 and smart_annotation_keyword.lower() in rich_text.lower():
        has_smart_link = any(ind in rich_text for ind in smart_annotation_indicators)
        if has_smart_link:
            score += 30
            feedback_parts.append(f"Smart annotation link to '{smart_annotation_keyword}' verified")
        else:
            feedback_parts.append(f"Text contains '{smart_annotation_keyword}' but it was typed as plain text, NOT a smart annotation link")
    else:
        feedback_parts.append(f"Smart annotation for '{smart_annotation_keyword}' not found in results")

    # Overall passing logic
    # Requires an overall score of 70, meaning they must successfully complete 
    # the smart annotation OR the table data perfectly alongside the image upload.
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": {
            "file_uploaded": file_uploaded,
            "table_created": table_count > 0,
            "text_created": text_count > 0,
            "smart_annotation_used": has_smart_link
        }
    }