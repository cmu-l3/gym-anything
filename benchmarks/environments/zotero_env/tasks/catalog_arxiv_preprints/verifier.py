#!/usr/bin/env python3
"""
Verifier for catalog_arxiv_preprints task.

Task: Update 'Library Catalog' and 'Call Number' fields for 3 papers.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_catalog_arxiv_preprints(traj, env_info, task_info):
    """
    Verify that the metadata fields were updated correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define targets
    targets = {
        "attention": {
            "name": "Attention Is All You Need",
            "catalog": "arXiv",
            "call_number": "1706.03762",
            "score_cat": 10,
            "score_call": 20
        },
        "bert": {
            "name": "BERT",
            "catalog": "arXiv",
            "call_number": "1810.04805",
            "score_cat": 10,
            "score_call": 20
        },
        "gan": {
            "name": "Generative Adversarial Nets",
            "catalog": "arXiv",
            "call_number": "1406.2661",
            "score_cat": 10,
            "score_call": 20
        }
    }
    
    # Load result
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

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Export script error: {result['error']}"}

    papers_data = result.get("papers", {})
    score = 0
    feedback_parts = []
    points_awarded = 0
    
    # Evaluate each paper
    for key, expected in targets.items():
        paper_data = papers_data.get(key, {})
        
        if not paper_data.get("found"):
            feedback_parts.append(f"Paper '{expected['name']}' not found in DB")
            continue

        # Check Library Catalog
        actual_cat = paper_data.get("catalog_value")
        if actual_cat and actual_cat.lower() == expected["catalog"].lower():
            score += expected["score_cat"]
            points_awarded += 1
        else:
            if actual_cat:
                feedback_parts.append(f"{expected['name']}: Catalog '{actual_cat}' != '{expected['catalog']}'")
            else:
                feedback_parts.append(f"{expected['name']}: Catalog empty")

        # Check Call Number (arXiv ID)
        actual_call = paper_data.get("call_number_value")
        # Be lenient with whitespace
        if actual_call:
            actual_call = actual_call.strip()
            
        if actual_call == expected["call_number"]:
            score += expected["score_call"]
            points_awarded += 1
        else:
            if actual_call:
                feedback_parts.append(f"{expected['name']}: ID '{actual_call}' != '{expected['call_number']}'")
            else:
                feedback_parts.append(f"{expected['name']}: ID empty")

    # Anti-gaming: Check if ANY paper was modified during task
    # We only penalize if score > 0 but no timestamps updated (suggests database was manipulated beforehand)
    any_modified = any(p.get("modified_during_task", False) for p in papers_data.values())
    
    if score > 0 and not any_modified:
        # Note: Timezone differences can make this flaky, so we usually don't zero the score completely
        # unless we are certain. For this task, we'll add a warning but keep score if values match.
        # However, we cleared values in setup, so they MUST have been added.
        # If timestamp didn't update, it's very suspicious.
        feedback_parts.append("Warning: Items do not appear modified during task window")

    # Final scoring
    if score == 100:
        feedback_parts.append("All metadata fields updated correctly")
    elif score >= 70:
        feedback_parts.append(f"Passed with score {score}/100")
    else:
        feedback_parts.append(f"Failed with score {score}/100")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }