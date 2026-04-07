#!/usr/bin/env python3
"""
Verifier for Contractor Access Request Screening task.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_contractor_access_request_screening(traj, env_info, task_info):
    """
    Verifies that Work Orders were created ONLY for Active vendors and contain correct info.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve result
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            local_path = tmp.name
        copy_from_env("/tmp/task_result.json", local_path)
        with open(local_path) as f:
            result = json.load(f)
        os.unlink(local_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Export error: {result['error']}"}

    all_wos = result.get("work_orders", [])
    initial_count = result.get("initial_count", 0)
    
    # We focus on the *new* WOs or filter by content since we don't have reliable timestamps in the simplified export.
    # However, since the setup counts existing WOs, valid entries should be > initial_count.
    # A robust way is to look for WOs that match the patterns we expect.

    metadata = task_info.get("metadata", {})
    expected_valid = metadata.get("expected_wos", [])
    traps = metadata.get("traps", [])

    score = 0
    feedback = []
    
    # Helper to check if a WO matches a spec
    def match_wo(wo, spec_vendor, spec_bld, spec_notes_keyword):
        desc = wo.get("description", "").lower()
        notes = wo.get("notes", "").lower()
        bld = wo.get("building_desc", "").lower()
        
        # Vendor check (in Description as requested)
        vendor_match = spec_vendor.lower() in desc
        # Building check
        bld_match = spec_bld.lower() in bld
        # Notes/Security check (can be in notes or description)
        sec_match = spec_notes_keyword.lower() in notes or spec_notes_keyword.lower() in desc
        
        return vendor_match, bld_match, sec_match

    # --- CRITERION 1: Valid Creations (45 pts) ---
    valid_found_count = 0
    
    for req in expected_valid:
        vendor = req["vendor"]
        bld = req["building_code"].replace("BLD-", "Building ") # Map code to name if needed
        sec = req["security"]
        
        found = False
        full_match = False
        
        for wo in all_wos:
            v_ok, b_ok, s_ok = match_wo(wo, vendor, bld, sec)
            if v_ok:
                found = True
                if b_ok and s_ok:
                    full_match = True
                    break # Found the perfect ticket
        
        if full_match:
            score += 15
            valid_found_count += 1
            feedback.append(f"SUCCESS: Created correct WO for {vendor}")
        elif found:
            score += 5 # Partial credit if vendor ticket exists but details wrong
            feedback.append(f"PARTIAL: Created WO for {vendor} but Building/Notes incorrect")
        else:
            feedback.append(f"FAIL: Missing WO for {vendor}")

    # --- CRITERION 2: Trap Avoidance (30 pts) ---
    trap_penalty = 0
    trap_hit = False
    for trap_vendor in traps:
        for wo in all_wos:
            desc = wo.get("description", "").lower()
            if trap_vendor.lower() in desc:
                trap_penalty += 15
                trap_hit = True
                feedback.append(f"FAIL: Created WO for suspended/missing vendor {trap_vendor}")
                break
    
    score_from_traps = 30 - trap_penalty
    if score_from_traps < 0: score_from_traps = 0
    score += score_from_traps

    # --- CRITERION 3: Security Notes (15 pts) ---
    # Already checked in full_match logic implicitly, but let's give explicit points if ANY note matched
    # Re-evaluating scoring to separate these concerns more clearly for the verifier output
    
    # Let's adjust:
    # 45 pts total for creation (15 per vendor) -> handled above
    # 30 pts for traps -> handled above
    # 15 pts for Notes specifically -> verify again
    # 10 pts for Building specifically -> verify again
    
    # We awarded full 15 per vendor above only if EVERYTHING matched. 
    # Let's decompose the valid_found logic to be granular as per the plan.
    
    # Reset and Recalculate based on plan:
    score = 0
    feedback = []
    
    # Check Active Vendors
    for req in expected_valid:
        vendor = req["vendor"]
        bld_keyword = "Building " + req["building_code"][-1] # "Building A"
        sec_keyword = req["security"]
        
        # Find best matching ticket
        best_wo = None
        for wo in all_wos:
            if vendor.lower() in wo.get("description", "").lower():
                best_wo = wo
                break
        
        if best_wo:
            score += 15 # Creation points (15 * 3 = 45 total)
            
            # Check Notes (5 pts each -> 15 total)
            notes_content = (best_wo.get("notes", "") + " " + best_wo.get("description", "")).lower()
            if sec_keyword.lower() in notes_content:
                score += 5
            else:
                feedback.append(f"Info: Missing security instructions for {vendor}")
                
            # Check Building (3.33 pts each -> ~10 total)
            bld_content = best_wo.get("building_desc", "").lower()
            if bld_keyword.lower() in bld_content:
                score += 3
            else:
                feedback.append(f"Info: Wrong building for {vendor}")
        else:
            feedback.append(f"Missing ticket for {vendor}")

    # Trap Checks (15 pts each -> 30 total)
    for trap in traps:
        hit = False
        for wo in all_wos:
            if trap.lower() in wo.get("description", "").lower():
                hit = True
                break
        if not hit:
            score += 15
        else:
            feedback.append(f"Trap triggered: Ticket created for {trap}")
            # Trap Cap Logic
            if trap == "Flow Plumbing": # The specific suspended one
                score = min(score, 50)
                feedback.append("Score capped at 50 due to Suspended vendor violation.")

    # Round score
    score = min(round(score), 100)
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {"wos_found": len(all_wos)}
    }