#!/usr/bin/env python3
"""
Verifier for repair_shift_scheduling_optimization task.

Evaluates the constraints directly against the exported schedule.csv file:
1. Coverage constraint (>= demand)
2. Turnaround constraint (no night -> morning)
3. Consecutive days constraint (<= 5 days)
4. Weekly minimums constraint (>= 4 shifts/week for FT)
5. Objective optimal (penalty <= 0, achievable due to slack in supply)

Anti-gaming:
Checks file modification timestamps.
Checks VS Code usage via VLM.
"""

import os
import json
import csv
import logging
import tempfile

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Constants matching the data generated in setup_task.sh
NUM_NURSES = 15
NUM_DAYS = 14
NUM_SHIFTS = 3
FT_NURSES = list(range(10))

# Vacation requests generated
VACATIONS = {
    0: [2, 3], 1: [5, 6], 2: [10, 11], 3: [0, 1], 4: [13],
    5: [7, 8], 6: [1, 2], 7: [9, 10], 8: [4, 5], 9: [12, 13],
    10: [6], 11: [3, 4], 12: [8, 9], 13: [0], 14: [11]
}

# Demand generated
DEMAND = {
    0: 3, # Morning
    1: 3, # Evening
    2: 2  # Night
}


def verify_optimization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve output
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        if not os.path.exists(temp_result.name) or os.path.getsize(temp_result.name) == 0:
            return {"passed": False, "score": 0, "feedback": "Result JSON not found"}

        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []

    # 1. Anti-gaming checks
    if not result.get("csv_modified_during_task", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "schedule.csv was not modified during the task. Did you run the script?"
        }

    csv_data = result.get("schedule_csv", "")
    if not csv_data:
        return {
            "passed": False,
            "score": 0,
            "feedback": "schedule.csv is empty or missing. Model may be infeasible."
        }
    
    # 2. Parse the CSV
    assigned = {n: {d: [] for d in range(NUM_DAYS)} for n in range(NUM_NURSES)}
    shift_counts = {d: {s: 0 for s in range(NUM_SHIFTS)} for d in range(NUM_DAYS)}

    try:
        reader = csv.DictReader(csv_data.strip().split('\n'))
        for row in reader:
            n = int(row['Nurse'])
            d = int(row['Day'])
            s = int(row['Shift'])
            assigned[n][d].append(s)
            shift_counts[d][s] += 1
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to parse schedule.csv: {e}"
        }

    score += 10
    feedback.append("[+] schedule.csv successfully generated and parsed (10/10)")

    # 3. Evaluate Constraints Logically
    # A. Coverage (>= Demand)
    coverage_ok = True
    for d in range(NUM_DAYS):
        for s in range(NUM_SHIFTS):
            if shift_counts[d][s] < DEMAND[s]:
                coverage_ok = False
                break
    
    if coverage_ok:
        score += 15
        feedback.append("[+] Coverage constraint met: All shifts >= demand (15/15)")
    else:
        feedback.append("[-] Coverage constraint violated: Understaffed shifts detected (0/15)")

    # B. Turnaround (no night -> morning)
    turnaround_ok = True
    for n in range(NUM_NURSES):
        for d in range(NUM_DAYS - 1):
            if 2 in assigned[n][d] and 0 in assigned[n][d+1]:
                turnaround_ok = False
                break
                
    if turnaround_ok:
        score += 15
        feedback.append("[+] Turnaround constraint met: No Night->Morning violations (15/15)")
    else:
        feedback.append("[-] Turnaround constraint violated: Night->Morning detected (0/15)")

    # C. Consecutive Days (<= 5)
    consec_ok = True
    for n in range(NUM_NURSES):
        for d in range(NUM_DAYS - 5):
            worked = sum(1 for i in range(6) if len(assigned[n][d+i]) > 0)
            if worked > 5:
                consec_ok = False
                break
                
    if consec_ok:
        score += 15
        feedback.append("[+] Consecutive days constraint met: <= 5 days (15/15)")
    else:
        feedback.append("[-] Consecutive days constraint violated: > 5 days detected (0/15)")

    # D. Weekly Minimums (>= 4 for FT)
    weekly_min_ok = True
    for n in FT_NURSES:
        for d in range(NUM_DAYS - 6):
            worked = sum(1 for i in range(7) if len(assigned[n][d+i]) > 0)
            if worked < 4:
                weekly_min_ok = False
                break
                
    if weekly_min_ok:
        score += 15
        feedback.append("[+] Weekly minimums constraint met: >= 4 shifts for FT nurses (15/15)")
    else:
        feedback.append("[-] Weekly minimums constraint violated: < 4 shifts for FT nurses (0/15)")

    # E. Objective Function (Penalty == 0 is perfectly achievable with 15 nurses for 112 shifts)
    penalty = 0
    for n in range(NUM_NURSES):
        for d in range(NUM_DAYS):
            if len(assigned[n][d]) > 0 and d in VACATIONS.get(n, []):
                penalty += 100
    
    if penalty == 0:
        score += 15
        feedback.append("[+] Objective optimal: 0 vacation penalties (15/15)")
    else:
        feedback.append(f"[-] Objective suboptimal: penalty is {penalty}, expected 0 (0/15)")

    # 4. VLM Trajectory Verification
    vlm_ok = False
    if query_vlm:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            prompt = """Analyze these screenshots of a VS Code session.
            Did the user edit the python file `schedule_model.py` and run it in the terminal?
            Look for evidence of editing code, writing logic, and terminal output.
            Reply in JSON: {"edited_and_ran_code": true/false}"""
            
            vlm_res = query_vlm(images=images, prompt=prompt)
            if vlm_res and vlm_res.get('parsed', {}).get('edited_and_ran_code', False):
                vlm_ok = True
                score += 15
                feedback.append("[+] VLM confirmed VS Code interaction and script execution (15/15)")
            else:
                feedback.append("[-] VLM could not confirm code editing and execution (0/15)")
        except Exception as e:
            logger.error(f"VLM verification failed: {e}")
            feedback.append("[-] VLM verification encountered an error")

    passed = (score >= 70 and coverage_ok and vlm_ok)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }