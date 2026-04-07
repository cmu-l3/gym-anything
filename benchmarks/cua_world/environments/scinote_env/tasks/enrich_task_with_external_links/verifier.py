#!/usr/bin/env python3
"""Verifier for enrich_task_with_external_links task."""

import json
import tempfile
import os
import re


def verify_enrich_task_with_external_links(traj, env_info, task_info):
    """Verify that the task description was correctly enriched with links and formatted text."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_neb_url = metadata.get('expected_neb_url', 'https://www.neb.com/products/m0386-cas9-nuclease-s-pyogenes')
    expected_addgene_url = metadata.get('expected_addgene_url', 'https://www.addgene.org/42230/')
    expected_warning = metadata.get('expected_warning_text', 'Keep enzymes on ice at all times')
    expected_bold = metadata.get('expected_bold_text', 'Critical:')

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/enrich_task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    if not result.get('task_found', False):
        return {"passed": False, "score": 0, "feedback": "Task 'Cas9 RNP Preparation' not found in database."}

    description = result.get('description', '')
    desc_lower = description.lower()
    
    task_start_time = int(result.get('task_start_time', 0))
    current_updated_at = int(result.get('current_updated_at', 0))

    # Anti-gaming: Ensure description was actually modified during the task
    was_modified = current_updated_at > task_start_time
    if was_modified:
        score += 10
        feedback_parts.append("Task description was modified during the session")
    else:
        feedback_parts.append(f"Task description was NOT modified during the session (updated_at: {current_updated_at} <= start_time: {task_start_time})")
        # If it wasn't modified, it's an automatic fail because the initial state was empty
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 1 (30 pts): NEB hyperlink
    # The URL might have trailing slashes or minor differences, so we check for inclusion inside an href
    neb_found = False
    if expected_neb_url in description or 'neb.com/products/m0386' in desc_lower:
        # Check if it's actually an href
        if re.search(r'href\s*=\s*["\'].*?neb\.com/products/m0386.*?["\']', desc_lower):
            neb_found = True
            score += 30
            feedback_parts.append("NEB hyperlink found")
        else:
            feedback_parts.append("NEB URL found, but not as a hyperlink (href)")
            score += 10 # Partial for getting the text
    else:
        feedback_parts.append("NEB URL not found")

    # Criterion 2 (30 pts): Addgene hyperlink
    addgene_found = False
    if expected_addgene_url in description or 'addgene.org/42230' in desc_lower:
        if re.search(r'href\s*=\s*["\'].*?addgene\.org/42230.*?["\']', desc_lower):
            addgene_found = True
            score += 30
            feedback_parts.append("Addgene hyperlink found")
        else:
            feedback_parts.append("Addgene URL found, but not as a hyperlink (href)")
            score += 10 # Partial for getting the text
    else:
        feedback_parts.append("Addgene URL not found")

    # Criterion 3 (10 pts): Warning text present
    warning_found = False
    if expected_warning.lower() in desc_lower:
        warning_found = True
        score += 10
        feedback_parts.append("Warning text found")
    else:
        feedback_parts.append("Warning text not found")

    # Criterion 4 (20 pts): Bold formatting for "Critical:"
    # Trix editor (SciNote's rich text) usually uses <strong>
    bold_found = False
    bold_pattern = r'<(strong|b)[^>]*>.*?critical:.*?</\1>'
    if re.search(bold_pattern, desc_lower):
        bold_found = True
        score += 20
        feedback_parts.append("'Critical:' is bolded")
    else:
        # Check if "Critical:" exists at all
        if expected_bold.lower() in desc_lower:
            feedback_parts.append("'Critical:' text found but not bolded")
            score += 5 # Partial for including the text
        else:
            feedback_parts.append("'Critical:' text not found")

    # Pass threshold: Must have actively modified, got at least one link right, and the warning text
    passed = was_modified and (neb_found or addgene_found) and warning_found and score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": {
            "was_modified": was_modified,
            "neb_link": neb_found,
            "addgene_link": addgene_found,
            "warning_text": warning_found,
            "bold_formatting": bold_found
        }
    }