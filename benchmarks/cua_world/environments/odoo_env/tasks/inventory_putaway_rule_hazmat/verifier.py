#!/usr/bin/env python3
"""
Verifier for inventory_putaway_rule_hazmat task.

Scoring System:
- Storage Locations Enabled (implied by creation of locs): 10 pts
- "Safety Cabinet 01" Created: 15 pts
- Putaway Rule Created: 35 pts
- Receipt Created & Validated (Transaction exists): 15 pts
- Auto-routing Verified (Item ended up in correct bin): 25 pts

Total: 100
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_inventory_putaway_rule_hazmat(traj, env_info, task_info):
    """
    Verify Odoo Putaway Rule configuration and usage.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    try:
        copy_from_env('/tmp/task_result.json', temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Locations Enabled (10 pts)
    # If they created a custom location, they must have enabled the setting or hacked it.
    if result.get("locations_enabled_proxy") and result.get("target_location_exists"):
        score += 10
        feedback.append("Storage Locations enabled.")
    elif result.get("locations_enabled_proxy"):
         score += 5 # Partial if enabled but location missing
         feedback.append("Storage Locations appear enabled.")
    else:
        feedback.append("Storage Locations not effectively enabled.")

    # 2. Location Created (15 pts)
    if result.get("target_location_exists"):
        score += 15
        feedback.append(f"Location '{result.get('target_location_name')}' created.")
    else:
        feedback.append("Target location 'Safety Cabinet 01' not found.")

    # 3. Putaway Rule Created (35 pts)
    if result.get("putaway_rule_exists"):
        score += 35
        feedback.append("Putaway rule correctly configured for Corrosives category.")
    else:
        feedback.append("Putaway rule linking Corrosives to Safety Cabinet not found.")

    # 4. Receipt Validated (15 pts)
    # We infer this from the existence of a stock move
    if result.get("receipt_validated"):
        score += 15
        feedback.append("Receipt transaction processed.")
    else:
        feedback.append("No completed receipt found for the hazardous product.")

    # 5. Auto-routing Verified (25 pts)
    if result.get("auto_routing_success"):
        score += 25
        feedback.append("Product successfully routed to Safety Cabinet.")
    else:
        feedback.append("Product did not end up in 'Safety Cabinet 01'.")

    # Pass Threshold: 75
    # Needed: Rule (35) + Location (15) + Routing (25) = 75
    # Or: All steps perfect = 100
    passed = score >= 75

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }