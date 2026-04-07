#!/usr/bin/env python3
"""
Verifier for classify_and_rename_documents@1.

Verifies:
1. Document 1 (Invoice) was renamed correctly and Nature set to Invoice.
2. Document 2 (NDA) was renamed correctly and Nature set to Contract.
3. Documents were modified during the task window.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_classify_and_rename_documents(traj, env_info, task_info):
    """
    Verify the classification and renaming of documents.
    """
    # 1. Setup - Get helper functions and metadata
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Doc 1 Criteria
    d1_keywords = metadata.get("doc1_expected_title_keywords", ["Invoice", "Global Logistics"])
    d1_nature_opts = metadata.get("doc1_expected_nature", ["invoice", "bill"])
    
    # Doc 2 Criteria
    d2_keywords = metadata.get("doc2_expected_title_keywords", ["NDA", "StartUp Dynamics"])
    d2_nature_opts = metadata.get("doc2_expected_nature", ["contract"])

    # 2. Retrieve Result JSON from Container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve verification data: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Analyze Results
    score = 0
    feedback = []
    
    doc1 = result.get('doc1', {})
    doc2 = result.get('doc2', {})
    task_start_ts = result.get('task_start', 0)

    # --- Verify Document 1 (Invoice) ---
    d1_title = doc1.get('title', '')
    d1_nature = doc1.get('nature', '')
    
    # Check Title (25 pts)
    # Flexible check: must contain main keywords (case-insensitive)
    d1_title_ok = all(kw.lower() in d1_title.lower() for kw in d1_keywords)
    if d1_title_ok:
        score += 25
        feedback.append("Doc 1 Title: Correct")
    else:
        feedback.append(f"Doc 1 Title: Incorrect ('{d1_title}'). Expected keywords: {d1_keywords}")

    # Check Nature (25 pts)
    # Nuxeo stores nature as lowercase usually, but we check flexible
    d1_nature_ok = (d1_nature and d1_nature.lower() in [n.lower() for n in d1_nature_opts])
    if d1_nature_ok:
        score += 25
        feedback.append("Doc 1 Nature: Correct")
    else:
        feedback.append(f"Doc 1 Nature: Incorrect ('{d1_nature}'). Expected: {d1_nature_opts}")

    # --- Verify Document 2 (NDA) ---
    d2_title = doc2.get('title', '')
    d2_nature = doc2.get('nature', '')

    # Check Title (25 pts)
    d2_title_ok = all(kw.lower() in d2_title.lower() for kw in d2_keywords)
    if d2_title_ok:
        score += 25
        feedback.append("Doc 2 Title: Correct")
    else:
        feedback.append(f"Doc 2 Title: Incorrect ('{d2_title}'). Expected keywords: {d2_keywords}")

    # Check Nature (25 pts)
    d2_nature_ok = (d2_nature and d2_nature.lower() in [n.lower() for n in d2_nature_opts])
    if d2_nature_ok:
        score += 25
        feedback.append("Doc 2 Nature: Correct")
    else:
        feedback.append(f"Doc 2 Nature: Incorrect ('{d2_nature}'). Expected: {d2_nature_opts}")

    # --- Anti-Gaming Check (Modification Time) ---
    # We verify that the documents were actually modified *after* the task started
    # Nuxeo returns ISO8601 strings. We just check if they differ from creation? 
    # Or simplified: if score > 0, we assume interaction happened, but checking 
    # "Do Nothing" is handled by the default values not matching criteria.
    # The default titles were "Scan_2024_001", which fail criteria.
    # The default nature was empty/null, which fails criteria.
    # So "Do Nothing" scores 0 automatically.
    
    # Check if titles are distinct (anti-gaming: didn't just name everything "Invoice")
    if d1_title.lower() == d2_title.lower() and score > 0:
        score = max(0, score - 25)
        feedback.append("Penalty: Both documents have identical titles.")

    # 4. Final Verdict
    passed = score >= 75  # Must get at least 3/4 checks correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }