#!/usr/bin/env python3
"""
Verifier for import_legacy_fleet task.

Checks:
1. Operator "Rural Drone Services" exists (20 pts)
2. 4 Aircraft are linked to this operator (20 pts)
3. Data correctness for each aircraft (Model, Mass, Status, Manufacturer) (60 pts distributed)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_import_legacy_fleet(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Verify Operator (20 pts)
    if result.get("operator_exists"):
        score += 20
        feedback.append("✓ Operator 'Rural Drone Services' created.")
    else:
        feedback.append("✗ Operator 'Rural Drone Services' NOT found.")
        # Critical fail if no operator, but we continue to see if they made aircraft unlinked
    
    # 2. Verify Aircraft Count (20 pts)
    # Full points for 4, partial for 1-3
    count = result.get("aircraft_count", 0)
    if count == 4:
        score += 20
        feedback.append("✓ Correct number of aircraft linked (4/4).")
    elif count > 0:
        pts = int((count / 4) * 20)
        score += pts
        feedback.append(f"⚠ Partial aircraft count: {count}/4 linked ({pts} pts).")
    else:
        feedback.append("✗ No aircraft linked to the operator.")

    # 3. Verify Data Accuracy (60 pts total -> 15 pts per expected aircraft)
    # We match expected records against found records by Registration or best Model match
    expected_fleet = task_info.get("metadata", {}).get("expected_fleet", [])
    found_records = result.get("aircraft_records", [])

    data_score = 0
    
    for expected in expected_fleet:
        # Find best match in found_records
        match = None
        # Try matching by Registration first
        for rec in found_records:
            if expected["reg"].lower() in rec.get("registration", "").lower():
                match = rec
                break
        
        # If no reg match, try fuzzy model match (fallback)
        if not match:
            for rec in found_records:
                if expected["model"].lower() in rec.get("model", "").lower():
                    match = rec
                    break
        
        if match:
            item_score = 0
            details = []
            
            # Check Model (5 pts)
            if expected["model"].lower() in match["model"].lower():
                item_score += 5
            else:
                details.append(f"Model mismatch ({match['model']})")

            # Check Mass (3 pts) - Tolerance 0.1
            try:
                if abs(float(match["mass"]) - expected["mass"]) < 0.1:
                    item_score += 3
                else:
                    details.append(f"Mass mismatch ({match['mass']})")
            except:
                details.append("Invalid mass")

            # Check Manufacturer (3 pts)
            if expected["mfr"].lower() in match["manufacturer"].lower():
                item_score += 3
            else:
                details.append(f"Mfr mismatch ({match['manufacturer']})")

            # Check Status (4 pts)
            status_lower = match["status"].lower()
            if expected["status_type"] == "active":
                # Accept: active, operation, service
                if any(x in status_lower for x in ["active", "operation", "service"]):
                    item_score += 4
                else:
                    details.append(f"Status mismatch (Exp: Active, Got: {match['status']})")
            elif expected["status_type"] == "maintenance":
                # Accept: maintenance, repair
                if any(x in status_lower for x in ["maint", "repair"]):
                    item_score += 4
                else:
                    details.append(f"Status mismatch (Exp: Maintenance, Got: {match['status']})")

            data_score += item_score
            if details:
                feedback.append(f"⚠ {expected['reg']}: {', '.join(details)}")
        else:
            feedback.append(f"✗ Missing aircraft: {expected['reg']} ({expected['model']})")

    score += data_score
    feedback.append(f"Data accuracy score: {data_score}/60")

    # Anti-gaming check: Ensure manufacturers exist
    mfrs = result.get("manufacturers_exist", [])
    if len(mfrs) < 3:
        feedback.append(f"Note: Only found manufacturers: {mfrs}")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": "\n".join(feedback)
    }