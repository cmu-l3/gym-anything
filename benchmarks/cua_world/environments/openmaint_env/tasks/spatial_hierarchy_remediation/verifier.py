#!/usr/bin/env python3
"""
Verifier for spatial_hierarchy_remediation task.

Scoring Breakdown (100 pts total):
- C1 (20 pts): Building addresses/cities corrected.
- C2 (20 pts): Floor parent buildings corrected.
- C3 (15 pts): Room parent floors corrected.
- C4 (15 pts): Duplicate room (ROOM-DUP-001) removed/inactive.
- C5 (15 pts): Room descriptions corrected.
- C6 (15 pts): Contamination room (ROOM-CONTAM-001) PRESERVED.

Score Cap: If C6 fails (contamination deleted), max score is 50.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_spatial_hierarchy_remediation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    current = data.get("current_state", {})
    baseline = data.get("baseline_config", {})
    expected_ids = baseline.get("ids", {})
    expected_values = baseline.get("expected_corrections", {})
    
    score = 0
    feedback = []

    # --- C1: Building Corrections (20 pts) ---
    # BLD-NORTH: Address "456 NW Flanders St"
    # BLD-SOUTH: Address "101 SW Columbia St"
    # BLD-EAST: City "Portland"
    
    c1_score = 0
    bld_state = current.get("buildings", {})
    
    # Check BLD-NORTH
    bn = bld_state.get("BLD-NORTH", {})
    if "456 NW Flanders St".lower() in bn.get("Address", "").lower():
        c1_score += 7
    
    # Check BLD-SOUTH
    bs = bld_state.get("BLD-SOUTH", {})
    if "101 SW Columbia St".lower() in bs.get("Address", "").lower():
        c1_score += 7
        
    # Check BLD-EAST
    be = bld_state.get("BLD-EAST", {})
    if "Portland".lower() in be.get("City", "").lower():
        c1_score += 6
        
    score += c1_score
    feedback.append(f"Building Corrections: {c1_score}/20")

    # --- C2: Floor Reassignment (20 pts) ---
    # FLR-N-02 -> BLD-NORTH ID
    # FLR-E-01 -> BLD-EAST ID
    
    c2_score = 0
    flr_state = current.get("floors", {})
    
    fn2 = flr_state.get("FLR-N-02", {})
    target_bn_id = expected_ids["buildings"]["BLD-NORTH"]
    if fn2.get("parent_building_id") == target_bn_id:
        c2_score += 10
        
    fe1 = flr_state.get("FLR-E-01", {})
    target_be_id = expected_ids["buildings"]["BLD-EAST"]
    if fe1.get("parent_building_id") == target_be_id:
        c2_score += 10
        
    score += c2_score
    feedback.append(f"Floor Reassignments: {c2_score}/20")

    # --- C3: Room Reassignment (15 pts) ---
    # RM-S-101 -> FLR-S-01 ID
    # RM-E-201 -> FLR-E-02 ID
    
    c3_score = 0
    rm_state = current.get("rooms", {})
    
    rs1 = rm_state.get("RM-S-101", {})
    target_fs1_id = expected_ids["floors"]["FLR-S-01"]
    if rs1.get("parent_floor_id") == target_fs1_id:
        c3_score += 7.5
        
    re2 = rm_state.get("RM-E-201", {})
    target_fe2_id = expected_ids["floors"]["FLR-E-02"]
    if re2.get("parent_floor_id") == target_fe2_id:
        c3_score += 7.5
        
    score += c3_score
    feedback.append(f"Room Reassignments: {c3_score}/15")

    # --- C4: Duplicate Removal (15 pts) ---
    # ROOM-DUP-001 should be deleted (exists=False) OR inactive
    
    c4_score = 0
    dup = rm_state.get("ROOM-DUP-001", {})
    if not dup.get("exists") or not dup.get("active"):
        c4_score = 15
        
    score += c4_score
    feedback.append(f"Duplicate Removal: {c4_score}/15")

    # --- C5: Description Fixes (15 pts) ---
    # RM-N-102: "Network Equipment Room 102"
    # RM-S-203: "Mechanical Plant Room 203"
    
    c5_score = 0
    rn102 = rm_state.get("RM-N-102", {})
    if "Network Equipment Room 102".lower() in rn102.get("Description", "").lower():
        c5_score += 7.5
        
    rs203 = rm_state.get("RM-S-203", {})
    if "Mechanical Plant Room 203".lower() in rs203.get("Description", "").lower():
        c5_score += 7.5
        
    score += c5_score
    feedback.append(f"Description Fixes: {c5_score}/15")

    # --- C6: Contamination Trap (15 pts) ---
    # ROOM-CONTAM-001 must exist AND be active
    
    c6_score = 0
    contam_deleted = False
    contam = rm_state.get("ROOM-CONTAM-001", {})
    
    if contam.get("exists") and contam.get("active"):
        c6_score = 15
    else:
        contam_deleted = True
        
    score += c6_score
    feedback.append(f"Contamination Trap: {c6_score}/15")

    # --- Anti-Gaming / Do Nothing Check ---
    # If score is 0, check if anything changed at all?
    # Actually, specific criteria check for changes. If 0, likely nothing done.

    # --- Score Cap ---
    if contam_deleted:
        feedback.append("PENALTY: Legitimate room ROOM-CONTAM-001 was deleted! Score capped at 50.")
        score = min(score, 50)

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }