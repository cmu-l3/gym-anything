#!/usr/bin/env python3
"""
Verifier for weekend_incident_log_entry task.
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

def verify_weekend_incident_log_entry(traj, env_info, task_info):
    """
    Scoring:
    - C1 (20pts): 4 valid new tickets created.
    - C2 (15pts): Correct codes used (SEC-MON-xxx).
    - C3 (15pts): Priorities match severity.
    - C4 (15pts): Building assignments correct.
    - C5 (15pts): No duplicates created (lighting/faucet).
    - C6 (20pts): False duplicate (ceiling tile) created.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment access failed"}

    # Load result
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            local_path = tmp.name
        copy_from_env("/tmp/wsl_result.json", local_path)
        with open(local_path) as f:
            result = json.load(f)
        os.unlink(local_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    new_tickets = result.get("new_tickets", [])
    b_map = result.get("baseline_map", {}) # "A" -> id, "B" -> id...
    
    score = 0
    feedback = []

    # Map expected incidents to found tickets
    expected = {
        "SEC-MON-001": {"b": "A", "p": ["critical", "high", "urgent"], "k": ["water", "pool", "server"]},
        "SEC-MON-002": {"b": "B", "p": ["high", "medium"], "k": ["window", "latch"]},
        "SEC-MON-003": {"b": "C", "p": ["medium", "normal"], "k": ["emergency", "light"]},
        "SEC-MON-004": {"b": "A", "p": ["medium", "normal", "low"], "k": ["ceiling", "tile", "sag"]} # The false duplicate
    }
    
    found_map = {} # Code -> ticket_obj
    
    # Heuristic matching: try to match new tickets to expected incidents
    for code, spec in expected.items():
        # 1. Try exact code match
        match = next((t for t in new_tickets if code.lower() in t.get("code", "").lower()), None)
        
        # 2. Try keyword match if no code match
        if not match:
            for t in new_tickets:
                desc = t.get("description", "").lower()
                if all(k in desc for k in spec["k"]):
                    match = t
                    break
        
        if match:
            found_map[code] = match
            # Remove from pool to avoid double counting (though typically 1:1)
    
    # C1: Count valid tickets found
    c1_count = len(found_map)
    score += c1_count * 5 # Max 20
    feedback.append(f"Found {c1_count}/4 valid incidents.")

    # C2: Code usage
    c2_score = 0
    for code, match in found_map.items():
        if code.lower() in match.get("code", "").lower():
            c2_score += 3.75
    score += round(c2_score)
    feedback.append(f"Correct codes used: {round(c2_score)} pts.")

    # C3: Priorities
    c3_score = 0
    for code, match in found_map.items():
        actual_p = match.get("priority", "")
        if any(p in actual_p for p in expected[code]["p"]):
            c3_score += 3.75
    score += round(c3_score)
    feedback.append(f"Priorities correct: {round(c3_score)} pts.")

    # C4: Buildings
    c4_score = 0
    for code, match in found_map.items():
        expected_b_key = expected[code]["b"]
        expected_b_id = b_map.get(expected_b_key)
        actual_b_id = match.get("building_id")
        
        # Loose matching on building ID string
        if expected_b_id and actual_b_id and str(expected_b_id) == str(actual_b_id):
            c4_score += 3.75
    score += round(c4_score)
    feedback.append(f"Buildings correct: {round(c4_score)} pts.")

    # C5: Check for duplicates (Bad tickets)
    # Duplicate 1: Lighting/Buzzing in A
    # Duplicate 2: Faucet in B
    duplicates_found = 0
    for t in new_tickets:
        if t in found_map.values(): continue # Already matched as valid
        
        desc = t.get("description", "").lower()
        # Check against duplicate keywords
        is_dup_1 = "light" in desc and "102" in desc and "buzz" in desc
        is_dup_2 = "faucet" in desc or ("sink" in desc and "restroom" in desc)
        
        if is_dup_1 or is_dup_2:
            duplicates_found += 1
    
    if duplicates_found == 0:
        score += 15
        feedback.append("No duplicates created.")
    else:
        feedback.append(f"Failed: {duplicates_found} duplicates created.")

    # C6: False Duplicate Trap (SEC-MON-004)
    # Did we find the ceiling tile ticket?
    if "SEC-MON-004" in found_map:
        score += 20
        feedback.append("False duplicate (Ceiling Tile) correctly identified and created.")
    else:
        feedback.append("Failed: False duplicate (Ceiling Tile) skipped.")
        if score > 65: score = 65 # Cap score if this trap is failed

    return {
        "passed": score >= 60,
        "score": int(score),
        "feedback": " ".join(feedback)
    }