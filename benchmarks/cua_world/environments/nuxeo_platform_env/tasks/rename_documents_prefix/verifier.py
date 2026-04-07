#!/usr/bin/env python3
"""
Verifier for rename_documents_prefix task.
Checks if the documents in Nuxeo Projects workspace have been renamed correctly.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_rename_documents_prefix(traj, env_info, task_info):
    """
    Verify that 3 documents were renamed with the 'PROJ-2023-' prefix.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define expected values
    expected_renames = {
        "/default-domain/workspaces/Projects/Annual-Report-2023": "PROJ-2023-Annual Report 2023",
        "/default-domain/workspaces/Projects/Project-Proposal": "PROJ-2023-Project Proposal",
        "/default-domain/workspaces/Projects/Q3-Status-Report": "PROJ-2023-Q3 Status Report"
    }

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    documents = result.get("documents", {})
    score = 0
    max_score = 100
    feedback_lines = []
    
    # Track criteria
    docs_correct = 0
    docs_partial = 0
    docs_exist = 0

    for path, expected_title in expected_renames.items():
        doc_info = documents.get(path, {})
        actual_title = doc_info.get("title", "MISSING")
        uid = doc_info.get("uid", "MISSING")

        if actual_title == "MISSING" or uid == "MISSING":
            feedback_lines.append(f"❌ Document not found at path: {path}")
            continue

        docs_exist += 1
        
        # Normalize for comparison (trim whitespace)
        actual_title_clean = actual_title.strip()
        
        if actual_title_clean == expected_title:
            score += 30
            docs_correct += 1
            feedback_lines.append(f"✅ {expected_title} (Correct)")
        elif actual_title_clean.startswith("PROJ-2023-"):
            # Partial credit for correct prefix but wrong remaining title
            score += 15
            docs_partial += 1
            feedback_lines.append(f"⚠️ {path}: Has prefix but title is '{actual_title_clean}' (Expected: '{expected_title}')")
        elif actual_title_clean == expected_title.replace("PROJ-2023-", ""):
             feedback_lines.append(f"❌ {path}: Title unchanged ('{actual_title_clean}')")
        else:
             feedback_lines.append(f"❌ {path}: Incorrect title '{actual_title_clean}'")

    # Bonus points for keeping all documents intact (10 pts)
    if docs_exist == 3:
        score += 10
        feedback_lines.append("✅ All documents preserved")
    else:
        feedback_lines.append("⚠️ Some documents are missing")

    # Cap score
    score = min(score, 100)
    
    # Pass threshold: Needs 80 points (approx 2 exact matches + preservation, or all 3 exact)
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_lines)
    }