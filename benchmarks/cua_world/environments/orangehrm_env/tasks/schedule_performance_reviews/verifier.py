#!/usr/bin/env python3
import json
import os
import tempfile
import sys

def verify_schedule_performance_reviews(traj, env_info, task_info):
    """
    Verifies that performance reviews were created and activated for Michael Chen and Sarah Jenkins.
    """
    # 1. Setup - Get Result JSON from container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Define Expectations
    expected_employees = ["Michael Chen", "Sarah Jenkins"]
    expected_reviewer = "Elena Fisher"
    expected_start = "2025-07-01"
    expected_end = "2025-12-31"
    expected_due = "2026-01-15"
    
    # OrangeHRM Status IDs: 1 usually 'Inactive', 2 usually 'Activated'/'In Progress'
    # We pass if status_id != 1
    
    reviews = result.get('reviews', [])
    
    score = 0
    feedback = []
    
    # Check Logic
    # We need to find a valid review for EACH employee
    found_employees = {}
    
    for r in reviews:
        emp = r['employee']
        if emp not in expected_employees:
            continue
            
        # Check constraints for this review
        reasons = []
        points = 0
        
        # 1. Reviewer (25 pts)
        if r['reviewer'] == expected_reviewer:
            points += 25
        else:
            reasons.append(f"Wrong reviewer ({r['reviewer']})")
            
        # 2. Status (Active) (25 pts)
        # Assuming status_id 1 is Inactive. Anything else is active/submitted
        if r['status_id'] != 1:
            points += 25
        else:
            reasons.append("Review not Activated (Status Inactive)")
            
        # 3. Dates (Start/End/Due) (25 pts) - All must match
        if (r['start_date'] == expected_start and 
            r['end_date'] == expected_end and 
            r['due_date'] == expected_due):
            points += 25
        else:
            reasons.append(f"Wrong dates ({r['start_date']} to {r['end_date']}, due {r['due_date']})")
            
        # Record best score for this employee
        if emp not in found_employees or points > found_employees[emp]['points']:
            found_employees[emp] = {
                'points': points,
                'reasons': reasons
            }

    # Calculate Final Score
    # Max score per employee = 75. 
    # Plus 25 global points if BOTH exist.
    # Total = 75 + 75 + 25 = 175? No, normalize to 100.
    
    # Let's do: 50 points per employee.
    # Per employee: 15 pts Reviewer, 15 pts Status, 10 pts Dates, 10 pts Existence
    
    final_score = 0
    
    for name in expected_employees:
        if name in found_employees:
            data = found_employees[name]
            # Base existence
            final_score += 10
            
            # Use the points calculated above but scale them
            # Above logic was 25/25/25 = 75 total
            # We want max 40 remaining points per employee
            # Scale factor: 40/75 = 0.53
            
            p = data['points']
            if p == 75: 
                final_score += 40 # Perfect
            else:
                final_score += int(p * 0.53)
                
            if data['reasons']:
                feedback.append(f"{name}: " + ", ".join(data['reasons']))
            else:
                feedback.append(f"{name}: Perfect")
        else:
            feedback.append(f"{name}: Review MISSING")

    return {
        "passed": final_score >= 95,
        "score": final_score,
        "feedback": "; ".join(feedback)
    }