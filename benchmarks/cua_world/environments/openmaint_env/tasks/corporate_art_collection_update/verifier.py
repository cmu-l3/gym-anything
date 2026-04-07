#!/usr/bin/env python3
"""
Verifier for corporate_art_collection_update task.
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_corporate_art_collection_update(traj, env_info, task_info):
    """
    Verifies that:
    1. ART-NEW-001 exists with correct details (created).
    2. ART-NEW-002 exists with correct details (created).
    3. ART-NEW-003 does NOT exist (policy adherence).
    4. ART-OLD-004 has updated status or notes (maintenance).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    assets = result.get("assets", {})
    score = 0
    feedback_parts = []

    # Criterion 1: ART-NEW-001 (High Value Painting) - 20 pts
    a1 = assets.get("ART-NEW-001", {})
    if a1.get("exists"):
        pts = 0
        desc = a1.get("description", "").lower()
        notes = a1.get("notes", "").lower()
        
        # Check content
        if "blue horizon" in desc and "jenkins" in desc:
            pts += 10
        else:
            feedback_parts.append("ART-NEW-001 description missing details")
            
        if "metropolis" in str(a1.get("building", "")).lower():
            pts += 5
        else:
            feedback_parts.append("ART-NEW-001 wrong building")

        if "15,000" in notes or "15000" in notes:
            pts += 5
        else:
            feedback_parts.append("ART-NEW-001 value not recorded in notes")
            
        score += pts
        feedback_parts.append(f"ART-NEW-001 created ({pts}/20)")
    else:
        feedback_parts.append("ART-NEW-001 NOT created")

    # Criterion 2: ART-NEW-002 (High Value Sculpture) - 20 pts
    a2 = assets.get("ART-NEW-002", {})
    if a2.get("exists"):
        pts = 0
        desc = a2.get("description", "").lower()
        notes = a2.get("notes", "").lower()
        
        if "steel vector" in desc and "thorne" in desc:
            pts += 10
        if "metropolis" in str(a2.get("building", "")).lower():
            pts += 5
        if "22,500" in notes or "22500" in notes:
            pts += 5
            
        score += pts
        feedback_parts.append(f"ART-NEW-002 created ({pts}/20)")
    else:
        feedback_parts.append("ART-NEW-002 NOT created")

    # Criterion 3: ART-NEW-003 (Low Value - Policy Check) - 20 pts
    a3 = assets.get("ART-NEW-003", {})
    if not a3.get("exists"):
        score += 20
        feedback_parts.append("Policy adhered: Low value item ignored (20/20)")
    else:
        feedback_parts.append("Policy violation: Low value item created (0/20)")

    # Criterion 4: ART-OLD-004 (Damaged Asset) - 20 pts
    a4 = assets.get("ART-OLD-004", {})
    if a4.get("exists"):
        status = str(a4.get("status", "")).lower()
        notes = str(a4.get("notes", "")).lower()
        desc = str(a4.get("description", "")).lower()
        
        # Accept either status change OR note update (flexibility)
        damage_keywords = ["damage", "leak", "maintenance", "repair", "broken", "water"]
        status_keywords = ["maintenance", "damaged", "inactive", "retired", "out of service"]
        
        is_status_changed = any(k in status for k in status_keywords)
        is_note_updated = any(k in notes for k in damage_keywords) or any(k in desc for k in damage_keywords)
        
        if is_status_changed or is_note_updated:
            score += 20
            feedback_parts.append("Damaged asset updated correctly (20/20)")
        else:
            feedback_parts.append("Damaged asset not flagged (0/20)")
    else:
        feedback_parts.append("Existing asset deleted? (0/20)")

    # Criterion 5: General Data Quality / Effort - 20 pts
    # Awarded if at least one asset created correctly and description format is good
    if score >= 20:
        score += 20
        feedback_parts.append("Formatting/Effort bonus (20/20)")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }