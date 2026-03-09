#!/usr/bin/env python3
"""
Verifier for bulk_import_assets task.

Verification Criteria:
1. Asset Count: Exactly 15 assets matching 'DEV-SF-%' (40 pts)
2. Sample Asset Mapping (DEV-SF-01):
   - Name is correct (Inventory Tag used as Name) (15 pts)
   - Serial Number is correct (Service Tag mapped correctly) (15 pts)
   - Site is correct (San Francisco) (15 pts)
   - Cost is imported (if retrievable) (15 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bulk_import_assets(traj, env_info, task_info):
    """
    Verify that assets were imported correctly from CSV.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_count = metadata.get('expected_count', 15)
    
    # Copy result file
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
    
    # 1. Check Count (40 pts)
    asset_count = int(result.get("asset_count", 0))
    if asset_count == expected_count:
        score += 40
        feedback_parts.append(f"Correctly imported {asset_count} assets.")
    elif asset_count > 0:
        partial = int((asset_count / expected_count) * 20)
        score += partial
        feedback_parts.append(f"Partial import: {asset_count}/{expected_count} assets found.")
    else:
        feedback_parts.append("No imported assets found.")
        return {"passed": False, "score": 0, "feedback": "No assets found in database"}

    # 2. Check Sample Asset Mapping
    sample = result.get("sample_asset", {})
    
    # Name Check (Inventory Tag -> Asset Name)
    if "DEV-SF-01" in sample.get("name_check", ""):
        score += 15
        feedback_parts.append("Asset Name mapping correct.")
    else:
        feedback_parts.append("Asset Name mapping incorrect (wrong field mapped?).")

    # Serial Check (Serial Number -> Service Tag/Serial No)
    if "C02XG1J2K3L4" in sample.get("serial_check", ""):
        score += 15
        feedback_parts.append("Serial Number mapping correct.")
    else:
        feedback_parts.append("Serial Number mapping incorrect.")

    # Site Check (Office -> Site)
    if "San Francisco" in sample.get("site_check", ""):
        score += 15
        feedback_parts.append("Site association correct.")
    else:
        feedback_parts.append("Site association incorrect (default or missing?).")

    # Cost Check (Unit Price -> Cost)
    # This is harder to verify precisely from raw text dump, but checking existence of value helps
    cost_val = sample.get("cost_data", "").strip()
    if cost_val and cost_val != "0" and cost_val != "0.0":
        score += 15
        feedback_parts.append(f"Cost data present ({cost_val}).")
    else:
        feedback_parts.append("Cost data missing or zero.")

    # Final result
    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }