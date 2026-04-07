#!/usr/bin/env python3
"""
Verifier for Event Support Ticket Consolidation task.

Scoring:
- Master Ticket Created: 20 pts
- Master Ticket Priority High: 10 pts
- Child 1 Linked: 15 pts
- Child 2 Linked: 15 pts
- Child 3 Linked: 15 pts
- Trap 1 (Galactic) Avoided: 15 pts
- Trap 2 (Closed) Avoided: 10 pts
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_event_support_ticket_consolidation(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Retrieve result file
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            local_path = tmp.name
        copy_from_env("/tmp/gala_result.json", local_path)
        with open(local_path) as f:
            result = json.load(f)
        os.unlink(local_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}

    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Task setup/export error: {result['error']}"}

    score = 0
    feedback = []
    
    # 1. Evaluate Master Ticket
    master = result.get("master_ticket", {})
    master_code = "UNKNOWN"
    
    if master.get("found"):
        score += 20
        feedback.append("Master ticket created (20/20)")
        master_code = master.get("code", "UNKNOWN")
        
        # Check Priority
        if str(master.get("priority_id")) == str(master.get("expected_high_id")):
            score += 10
            feedback.append("Master priority is High (10/10)")
        else:
            feedback.append("Master priority incorrect (0/10)")
    else:
        feedback.append("Master ticket NOT found (0/30)")

    # 2. Evaluate Children Links
    # We look for "Parent:" and ideally the master code
    ticket_states = result.get("ticket_states", {})
    
    children = ['child_1', 'child_2', 'child_3']
    for role in children:
        state = ticket_states.get(role, {})
        if not state.get("exists"):
            feedback.append(f"{role} deleted! (0/15)")
            continue
            
        desc = state.get("description", "")
        # Check for appended text
        # Criteria: Must contain "Parent:" AND (MasterCode OR "Master")
        # We allow flexibility if they didn't capture the exact code but clearly tried to link
        linked = False
        if "Parent:" in desc:
            if master_code != "UNKNOWN" and master_code in desc:
                linked = True
            elif "Master" in desc or "master" in desc:
                linked = True
            # If code is unknown but they appended something that looks like a code, giving benefit of doubt?
            # Strict mode: must match instruction
            elif master_code != "UNKNOWN": 
                # Agent created master but didn't use its code in child?
                pass
                
        if linked:
            score += 15
            feedback.append(f"{role} linked correctly (15/15)")
        else:
            feedback.append(f"{role} not linked correctly (0/15)")

    # 3. Evaluate Traps
    # Trap 1: Galactic (Keyword trap)
    t1 = ticket_states.get("trap_keyword", {})
    if t1.get("exists"):
        curr_d = t1.get("description", "")
        orig_d = t1.get("original_desc", "")
        if "Parent" not in curr_d and curr_d == orig_d:
            score += 15
            feedback.append("Trap 'Galactic' avoided (15/15)")
        else:
            feedback.append("Trap 'Galactic' modified (0/15)")
    else:
        feedback.append("Trap 'Galactic' deleted (0/15)")

    # Trap 2: Closed (Status trap)
    t2 = ticket_states.get("trap_closed", {})
    if t2.get("exists"):
        curr_d = t2.get("description", "")
        orig_d = t2.get("original_desc", "")
        if "Parent" not in curr_d and curr_d == orig_d:
            score += 10
            feedback.append("Trap 'Closed/Catering' avoided (10/10)")
        else:
            feedback.append("Trap 'Closed/Catering' modified (0/10)")
    else:
        feedback.append("Trap 'Closed/Catering' deleted (0/10)")

    return {
        "passed": score >= 65,
        "score": score,
        "feedback": " | ".join(feedback)
    }