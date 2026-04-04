#!/usr/bin/env python3
"""
Verifier for catalog_non_traditional_materials task.

Verifies:
1. Collection "Reproducibility Data" exists.
2. Item "Scikit-learn" exists in that collection (Computer Program).
3. Item "MNIST Database" exists in that collection (Dataset).
4. Metadata fields match specific requirements.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_catalog_non_traditional_materials(traj, env_info, task_info):
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load results
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
    feedback = []
    
    # 1. Collection Verification (10 pts)
    if result.get("collection_found"):
        score += 10
        feedback.append("Collection 'Reproducibility Data' created.")
    else:
        return {"passed": False, "score": 0, "feedback": "Collection 'Reproducibility Data' NOT found."}

    items = result.get("items_found", [])
    
    # Helpers for item matching
    def find_item_by_title(title_fragment):
        for item in items:
            # Title is fieldID 1 (usually), or mapped to 'title' in our export script
            if "title" in item.get("fields", {}) and title_fragment.lower() in item["fields"]["title"].lower():
                return item
        return None

    # 2. Verify Scikit-learn (Computer Program)
    sklearn = find_item_by_title("Scikit-learn")
    if sklearn:
        score += 10 # Item exists in collection
        feedback.append("Item 'Scikit-learn' found in collection.")
        
        # Check Type
        if sklearn.get("type") == "computerProgram":
            score += 10
            feedback.append("Correct item type (Computer Program).")
        else:
            feedback.append(f"Incorrect item type: {sklearn.get('type')} (expected computerProgram).")

        # Check Fields
        fields = sklearn.get("fields", {})
        
        # Version (10 pts)
        if fields.get("version") == "1.0.2":
            score += 10
            feedback.append("Correct Version.")
        else:
            feedback.append(f"Incorrect Version: {fields.get('version')}.")

        # System (5 pts)
        if fields.get("system") == "Python":
            score += 5
            feedback.append("Correct System.")
        else:
            feedback.append(f"Incorrect System: {fields.get('system')}.")

        # URL (5 pts)
        # Zotero sometimes normalizes URLs, so we check contains or exact
        if "scikit-learn.org" in fields.get("url", ""):
            score += 5
            feedback.append("Correct URL.")
        else:
            feedback.append(f"Incorrect URL: {fields.get('url')}.")
            
        # Company (5 pts) - Sometimes mapped to 'company', sometimes 'publisher' depending on view
        company = fields.get("company") or fields.get("publisher")
        if company and "Scikit-learn Developers" in company:
             # Bonus check for partial match if needed, but exact is requested
             score += 5
             feedback.append("Correct Company/Publisher.")
        else:
             feedback.append(f"Incorrect Company: {company}.")

    else:
        feedback.append("Item 'Scikit-learn' NOT found in collection.")

    # 3. Verify MNIST (Dataset)
    mnist = find_item_by_title("MNIST")
    if mnist:
        score += 10 # Item exists in collection
        feedback.append("Item 'MNIST Database' found in collection.")

        # Check Type
        if mnist.get("type") == "dataset":
            score += 10
            feedback.append("Correct item type (Dataset).")
        else:
            feedback.append(f"Incorrect item type: {mnist.get('type')} (expected dataset).")

        # Check Fields
        fields = mnist.get("fields", {})

        # Date (10 pts)
        if "1998" in fields.get("date", ""):
            score += 10
            feedback.append("Correct Date.")
        else:
            feedback.append(f"Incorrect Date: {fields.get('date')}.")

        # Repository (10 pts)
        if fields.get("repository") == "Courant Institute":
            score += 10
            feedback.append("Correct Repository.")
        else:
            feedback.append(f"Incorrect Repository: {fields.get('repository')}.")

        # URL (10 pts)
        if "yann.lecun.com" in fields.get("url", ""):
            score += 10
            feedback.append("Correct URL.")
        else:
             feedback.append(f"Incorrect URL: {fields.get('url')}.")

    else:
        feedback.append("Item 'MNIST Database' NOT found in collection.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }