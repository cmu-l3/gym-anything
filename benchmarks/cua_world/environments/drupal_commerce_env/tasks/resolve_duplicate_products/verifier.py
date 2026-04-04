#!/usr/bin/env python3
"""
Verifier for resolve_duplicate_products task.

Criteria:
1. All 4 Duplicate products (SKU 'IMPORT-%') must be deleted.
2. The Bose product (SKU 'BOSE-QCU') price must be corrected to 429.00.
3. Original products must NOT be deleted.
4. Final catalog count should be exactly 10.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_resolve_duplicate_products(traj, env_info, task_info):
    """
    Verify cleanup of duplicates and price correction.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    # Extract Data
    remaining_duplicates = int(result.get("remaining_duplicates_count", 99))
    bose_price = float(result.get("bose_final_price", 0.0))
    originals_exist = result.get("originals_exist", False)
    # Handle string 'true'/'false' if bash json creation wasn't perfect types
    if isinstance(originals_exist, str):
        originals_exist = originals_exist.lower() == 'true'
        
    final_count = int(result.get("final_product_count", 0))
    
    score = 0
    feedback_parts = []
    
    # 1. Duplicates Deleted (Max 60 points, 15 per duplicate)
    # We started with 4. Score is based on how many are gone.
    deleted_count = 4 - remaining_duplicates
    if deleted_count < 0: deleted_count = 0 # Should not happen unless agent added more?
    
    score += (deleted_count * 15)
    if remaining_duplicates == 0:
        feedback_parts.append("All duplicates deleted successfully.")
    else:
        feedback_parts.append(f"{remaining_duplicates} duplicates still remain.")

    # 2. Price Correction (Max 15 points)
    # Target is 429.00. Allow small float epsilon.
    if abs(bose_price - 429.00) < 0.01:
        score += 15
        feedback_parts.append("Bose price corrected to $429.00.")
    elif abs(bose_price - 329.00) < 0.01:
        feedback_parts.append("Bose price still incorrect ($329.00).")
    else:
        feedback_parts.append(f"Bose price is {bose_price} (expected 429.00).")

    # 3. Originals Preservation (Max 15 points)
    if originals_exist:
        score += 15
        feedback_parts.append("Original products preserved.")
    else:
        # Severe penalty if originals are lost, but we just don't give points here.
        # The Pass threshold will handle the failure.
        missing = result.get("missing_originals", "").strip()
        feedback_parts.append(f"Original products deleted: {missing}")

    # 4. Final Count Check (Max 10 points)
    # If duplicates gone (4) and originals kept (10), total should be 10.
    if final_count == 10:
        score += 10
        feedback_parts.append("Catalog count is correct (10).")
    else:
        feedback_parts.append(f"Catalog count is {final_count} (expected 10).")

    # Safety Gate: If ANY original is missing, cap the score at 40 (Fail).
    # Deleting the wrong data is a critical failure in admin tasks.
    if not originals_exist:
        score = min(score, 40)
        feedback_parts.append("CRITICAL: Original data loss detected.")

    passed = score >= 70 and originals_exist

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }