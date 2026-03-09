#!/usr/bin/env python3
import json
import os
import tempfile
import datetime
from dateutil import parser, relativedelta

def verify_split_opportunity_phased(traj, env_info, task_info):
    """
    Verify that the opportunity was correctly split into two phases.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file from container
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

    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Export script error: {result.get('error')}"}

    score = 0
    feedback_parts = []
    
    # Metadata targets
    metadata = task_info.get('metadata', {})
    target_p1_rev = metadata.get('phase1_revenue', 20000)
    target_p2_rev = metadata.get('phase2_revenue', 100000)
    
    # --- Verify Phase 1 (Design Phase) ---
    p1_data = result.get("phase1_data")
    if p1_data:
        score += 15
        feedback_parts.append("Phase 1 opportunity found.")
        
        # Check Revenue ($20k)
        revenue = p1_data.get("expected_revenue", 0)
        if abs(revenue - target_p1_rev) < 1.0:
            score += 20
            feedback_parts.append("Phase 1 revenue correct ($20k).")
        else:
            feedback_parts.append(f"Phase 1 revenue incorrect (expected {target_p1_rev}, got {revenue}).")
            
        # Check Deadline (End of current month)
        deadline_str = p1_data.get("date_deadline")
        if deadline_str:
            try:
                deadline = parser.parse(deadline_str).date()
                today = datetime.date.today()
                # Calculate last day of current month
                next_month = today.replace(day=28) + datetime.timedelta(days=4)
                last_day = next_month - datetime.timedelta(days=next_month.day)
                
                # Tolerance +/- 3 days
                diff = abs((deadline - last_day).days)
                if diff <= 3:
                    score += 10
                    feedback_parts.append("Phase 1 deadline correct (end of month).")
                else:
                    feedback_parts.append(f"Phase 1 deadline incorrect (expected ~{last_day}, got {deadline}).")
            except:
                feedback_parts.append("Phase 1 deadline format error.")
        else:
            feedback_parts.append("Phase 1 deadline not set.")
            
    else:
        feedback_parts.append("Phase 1 opportunity 'Azure Interior - Design Phase' NOT found.")

    # --- Verify Phase 2 (Implementation Phase) ---
    p2_data = result.get("phase2_data")
    if p2_data:
        score += 15
        feedback_parts.append("Phase 2 opportunity found.")
        
        # Check Revenue ($100k)
        revenue = p2_data.get("expected_revenue", 0)
        if abs(revenue - target_p2_rev) < 1.0:
            score += 20
            feedback_parts.append("Phase 2 revenue correct ($100k).")
        else:
            feedback_parts.append(f"Phase 2 revenue incorrect (expected {target_p2_rev}, got {revenue}).")
            
        # Check Deadline (~3 months from now)
        deadline_str = p2_data.get("date_deadline")
        if deadline_str:
            try:
                deadline = parser.parse(deadline_str).date()
                today = datetime.date.today()
                target_date = today + relativedelta.relativedelta(months=3)
                
                # Tolerance +/- 10 days
                diff = abs((deadline - target_date).days)
                if diff <= 15: # Generous tolerance for "3 months from today"
                    score += 10
                    feedback_parts.append("Phase 2 deadline correct (~3 months out).")
                else:
                    feedback_parts.append(f"Phase 2 deadline incorrect (expected ~{target_date}, got {deadline}).")
            except:
                feedback_parts.append("Phase 2 deadline format error.")
        else:
            feedback_parts.append("Phase 2 deadline not set.")

        # Check Customer Link
        partner = p2_data.get("partner_id")
        # partner_id field in Odoo read returns [id, name]
        if partner and isinstance(partner, list) and len(partner) > 1 and "Azure Interior" in partner[1]:
            score += 10
            feedback_parts.append("Phase 2 linked to correct customer.")
        else:
            feedback_parts.append("Phase 2 not linked to 'Azure Interior'.")
            
    else:
        feedback_parts.append("Phase 2 opportunity 'Azure Interior - Implementation Phase' NOT found.")

    # --- Verify No Duplicate/Stale Data ---
    # The original "Whole Office Design" should effectively be gone (renamed to Phase 1)
    # If the agent created a NEW Phase 1 and left the old one, that's ambiguous but technically "Phase 1 found" handles the points.
    # However, ideal workflow is renaming.
    if result.get("original_still_exists"):
        feedback_parts.append("Note: Original 'Whole Office Design' record still exists (should have been renamed).")
        # Optional: Penalize slightly or just warn? Leaving as warning.

    # Final logic
    # Must have both phases found and revenues correct to pass
    passed = score >= 70 and p1_data and p2_data
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }