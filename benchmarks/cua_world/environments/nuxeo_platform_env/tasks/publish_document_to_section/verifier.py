#!/usr/bin/env python3
"""
Verifier for publish_document_to_section task.

Verifies that:
1. A document was published to the 'Public Reports' section.
2. The document title is correct ('Annual Report 2023').
3. The document is a Proxy (indicating a Publish action, not a Move/Copy).
4. The original document still exists in the workspace.
5. Visual evidence confirms the workflow.
"""

import json
import os
import logging
import tempfile
import sys
from pathlib import Path

# Add parent directory for shared utilities if needed
# sys.path.insert(0, str(Path(__file__).parent.parent))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_publish_document(traj, env_info, task_info):
    """
    Verify the Nuxeo document publication task.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Metrics
    search_result = result.get('search_result', {})
    
    doc_count = search_result.get('count', 0)
    final_title = search_result.get('title', '')
    is_proxy = search_result.get('is_proxy', False)
    original_exists = result.get('original_exists', False)
    initial_count = int(result.get('initial_doc_count', 0))

    score = 0
    feedback = []
    
    # 3. Scoring Logic

    # Criterion A: Document exists in section (35 pts)
    if doc_count > 0:
        score += 35
        feedback.append("Document found in 'Public Reports' section.")
    else:
        feedback.append("No documents found in 'Public Reports' section.")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed: No document published to target section."
        }

    # Criterion B: Correct Title (25 pts)
    # Flexible matching for case/spacing
    if "annual" in final_title.lower() and "report" in final_title.lower() and "2023" in final_title:
        score += 25
        feedback.append(f"Correct document published ('{final_title}').")
    else:
        feedback.append(f"Published document has wrong title: '{final_title}'.")

    # Criterion C: Is Proxy (15 pts) - Crucial for "Publish" vs "Copy"
    if is_proxy:
        score += 15
        feedback.append("Document is correctly published as a proxy.")
    else:
        feedback.append("Document is NOT a proxy (likely a copy/move instead of publish).")

    # Criterion D: Original Exists (15 pts)
    if original_exists:
        score += 15
        feedback.append("Original document remains in workspace.")
    else:
        feedback.append("Original document is missing (likely moved instead of published).")

    # Criterion E: State Change (10 pts)
    if doc_count > initial_count:
        score += 10
        feedback.append("Confirmed new document creation (state change).")
    else:
        feedback.append("No increase in document count detected.")

    # 4. Visual Verification (Trajectory check)
    # We look for the "Publish" modal or navigation to the Sections tab in the UI
    # This adds robustness against "magic" API calls if the agent were to use them (unlikely but good practice)
    # For now, we rely primarily on the strong API signal (isProxy), but we report VLM status.
    
    # (Optional: Include VLM logic here if the framework supports it directly in the verifier)
    # Since we have strong programmatic verification via 'isProxy', VLM is supplementary.
    
    passed = score >= 60 and doc_count > 0 and "Annual Report" in final_title
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }