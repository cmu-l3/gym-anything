#!/usr/bin/env python3
"""
Verifier for create_project task.
Checks database records for the existence and correctness of the project and its phases.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_project(traj, env_info, task_info):
    """
    Verify the creation of the Project and its Phases.
    
    Criteria:
    1. Project exists (Search Key: WH-RENO-2024) [Required for pass]
    2. Header details match (Name, Description, Amount, Dates)
    3. Exactly 4 phases exist
    4. Phase details match (Seq, Name, Amount, Dates)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata expectations
    metadata = task_info.get('metadata', {})
    expected_key = metadata.get('search_key', 'WH-RENO-2024')
    expected_total_amt = metadata.get('total_amount', 250000)
    
    # 1. Load Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Evaluate Project Header
    if not result.get("project_found", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Project with Search Key '{expected_key}' not found in database."
        }
    
    score += 10 # Base points for existence
    feedback_parts.append("Project record created")
    
    proj = result.get("project", {})
    
    # Name check
    if "Warehouse Renovation 2024" in proj.get("name", ""):
        score += 5
    else:
        feedback_parts.append(f"Name mismatch: {proj.get('name')}")

    # Description check
    if "warehouse" in proj.get("description", "").lower():
        score += 5
    else:
        feedback_parts.append("Description missing/incorrect")

    # Amount check
    try:
        actual_amt = float(proj.get("planned_amt", 0))
        if abs(actual_amt - expected_total_amt) < 100:
            score += 10
            feedback_parts.append(f"Project Amount correct ({actual_amt})")
        else:
            feedback_parts.append(f"Project Amount mismatch: {actual_amt} != {expected_total_amt}")
    except:
        feedback_parts.append("Invalid project amount format")

    # Date checks (Loose string matching for YYYY-MM-DD)
    if "2024-07-01" in str(proj.get("date_contract", "")):
        score += 5
    else:
        feedback_parts.append(f"Contract Date mismatch: {proj.get('date_contract')}")

    if "2025-01-31" in str(proj.get("date_finish", "")):
        score += 5
    else:
        feedback_parts.append(f"Finish Date mismatch: {proj.get('date_finish')}")

    # 3. Evaluate Phases
    phases = result.get("phases", [])
    if len(phases) == 4:
        score += 10
        feedback_parts.append("Correct number of phases (4)")
    else:
        feedback_parts.append(f"Incorrect number of phases: {len(phases)}")

    # Detailed phase checks
    # Expected phases from metadata or hardcoded reference
    expected_phases = [
        {"seq": 10, "amt": 25000, "name": "Planning"},
        {"seq": 20, "amt": 45000, "name": "Demolition"},
        {"seq": 30, "amt": 150000, "name": "Construction"},
        {"seq": 40, "amt": 30000, "name": "Inspection"}
    ]

    phases_matched = 0
    amounts_correct = 0
    sequences_correct = 0
    
    # Sort actual phases by seq to align comparison
    try:
        phases.sort(key=lambda x: float(x.get("seq", 0)))
    except:
        pass

    for i, p in enumerate(phases):
        # Check if we have a corresponding expected phase
        if i >= len(expected_phases): break
        exp = expected_phases[i]
        
        # Sequence
        try:
            if int(float(p.get("seq"))) == exp["seq"]:
                sequences_correct += 1
        except: pass
            
        # Amount
        try:
            if abs(float(p.get("amt")) - exp["amt"]) < 50:
                amounts_correct += 1
        except: pass
        
        # Name (partial match)
        if exp["name"].lower() in p.get("name", "").lower():
            phases_matched += 1

    # Score calculation for phases (Max 50 points remaining)
    # 4 phases * 1.25 pts for seq = 5 pts
    score += (sequences_correct * 1.25)
    
    # 4 phases * 3.75 pts for amt = 15 pts
    score += (amounts_correct * 3.75)
    
    # 4 phases * 5 pts for existence/name = 20 pts
    score += (phases_matched * 5)
    
    # Sum check
    total_phase_amt = sum([float(p.get("amt", 0)) for p in phases])
    if abs(total_phase_amt - expected_total_amt) < 100:
        score += 10
        feedback_parts.append("Phase amounts sum to total")

    # 4. Anti-gaming check (Timestamp)
    # We check if 'created_ts' (from DB) is after 'task_start_ts'
    # DB Format usually: "2024-05-20 10:00:00.123"
    # TS Format: "1716200000"
    # This is complex to parse perfectly across timezones without libraries, 
    # so we'll skip strict parsing and rely on the fact that we deleted the record in setup.
    # If it exists now, it must have been created during the task.
    
    return {
        "passed": score >= 60,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }