#!/usr/bin/env python3
"""
Verifier for correct_invoice_metadata task.

Checks:
1. Did the agent update the document title to match the Invoice Number?
2. Did the agent update the Source field to match the Vendor?
3. Did the agent update the Description field to include the Amount?
4. Was the document actually modified during the task duration?
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_correct_invoice_metadata(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Check basic existence
    if not result.get("doc_exists"):
        return {"passed": False, "score": 0, "feedback": "The document 'Scanned-Invoice' was not found."}

    # Extract Ground Truth
    gt = result.get("ground_truth", {})
    gt_invoice = gt.get("invoice_number", "").strip()
    gt_vendor = gt.get("vendor", "").strip()
    gt_amount = gt.get("amount", "").strip() # e.g. "$1,234.56"

    # Extract Actual Document Metadata
    doc_meta = result.get("document_metadata", {})
    props = doc_meta.get("properties", {})
    
    act_title = props.get("dc:title", "").strip()
    act_source = props.get("dc:source", "").strip()
    act_desc = props.get("dc:description", "").strip()

    # Scoring
    score = 0
    feedback_items = []
    
    # Check 1: Title (Invoice Number) - 40 pts
    # Exact match required
    if act_title == gt_invoice:
        score += 40
        feedback_items.append(f"✓ Title correctly updated to '{act_title}'")
    else:
        feedback_items.append(f"✗ Title mismatch: Expected '{gt_invoice}', got '{act_title}'")

    # Check 2: Source (Vendor) - 30 pts
    # Exact match required
    if act_source == gt_vendor:
        score += 30
        feedback_items.append(f"✓ Source correctly updated to '{act_source}'")
    else:
        feedback_items.append(f"✗ Source mismatch: Expected '{gt_vendor}', got '{act_source}'")

    # Check 3: Description (Amount) - 30 pts
    # Containment check (allow for "Total: $100" or just "$100")
    # Clean up currency symbols for robust check if needed, but task specifies exact amount
    if gt_amount in act_desc:
        score += 30
        feedback_items.append(f"✓ Description contains amount '{gt_amount}'")
    elif gt_amount.replace(",", "") in act_desc.replace(",", ""): # Allow missing comma
        score += 30
        feedback_items.append(f"✓ Description contains amount '{gt_amount}' (ignoring formatting)")
    else:
        feedback_items.append(f"✗ Description missing amount: Expected '{gt_amount}' in '{act_desc}'")

    # Check 4: Modification Timestamp (Anti-Gaming)
    if not result.get("doc_modified", False):
        score = 0
        feedback_items.append("! Anti-gaming: Document was NOT modified during the task window.")

    # Pass Threshold
    passed = score == 100

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_items)
    }