#!/usr/bin/env python3
"""
Verifier for bls_career_comparison task.

Scoring Criteria:
1. Firefox History (15 pts): Visited ≥3 distinct BLS OOH pages.
2. Bookmarks (20 pts): 'Career Research' folder exists (10) with ≥3 BLS bookmarks (10).
3. JSON Structure (20 pts): File exists, fresh, has 3 keys.
4. Data Accuracy (30 pts): Wage, growth, jobs, education fall within plausible ranges.
5. Summary (15 pts): Summary file exists and contains occupation names.

Pass Threshold: 60/100
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Ranges allowing for some variation between 2022-2024 data
# Wages are approximate medians
RANGES = {
    "registered_nurses": {
        "wage": (70000, 110000), "growth": (2, 15), "jobs": (2500000, 4000000), "edu": ["bachelor", "degree"]
    },
    "software_developers": {
        "wage": (100000, 175000), "growth": (15, 35), "jobs": (1500000, 2500000), "edu": ["bachelor", "degree"]
    },
    "electricians": {
        "wage": (45000, 85000), "growth": (2, 15), "jobs": (650000, 1200000), "edu": ["high school", "diploma", "equivalent"]
    }
}

def verify_bls_career_comparison(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
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

    score = 0
    feedback = []

    # 1. Firefox History (15 pts)
    visits = result.get("bls_history_visits", 0)
    if visits >= 3:
        score += 15
        feedback.append(f"History Check: Visited {visits} BLS OOH pages (15/15).")
    elif visits > 0:
        score += 5
        feedback.append(f"History Check: Visited only {visits} BLS pages (5/15).")
    else:
        feedback.append("History Check: No BLS OOH visits detected (0/15).")

    # 2. Bookmarks (20 pts)
    if result.get("bookmark_folder_exists"):
        score += 10
        feedback.append("Bookmark Check: 'Career Research' folder found (10/10).")
        count = result.get("bls_bookmark_count", 0)
        if count >= 3:
            score += 10
            feedback.append(f"Bookmark Check: Found {count} BLS bookmarks (10/10).")
        else:
            score += int(count * 3.3)
            feedback.append(f"Bookmark Check: Found only {count} BLS bookmarks (Partial).")
    else:
        feedback.append("Bookmark Check: 'Career Research' folder missing (0/20).")

    # 3. JSON Structure & Existence (20 pts)
    json_content = result.get("json_content", {})
    if result.get("json_exists") and result.get("json_fresh"):
        score += 10
        feedback.append("JSON File: Exists and is fresh (10/10).")
        
        # Check keys
        keys_found = 0
        required_keys = ["registered_nurses", "software_developers", "electricians"]
        for k in required_keys:
            if k in json_content:
                keys_found += 1
        
        if keys_found == 3:
            score += 10
            feedback.append("JSON Structure: All 3 occupations present (10/10).")
        else:
            partial = int((keys_found / 3) * 10)
            score += partial
            feedback.append(f"JSON Structure: Found {keys_found}/3 occupations ({partial}/10).")
    else:
        feedback.append("JSON File: Missing or not created during task (0/20).")

    # 4. Data Accuracy (30 pts - 10 per occupation)
    for occ, range_data in RANGES.items():
        occ_score = 0
        data = json_content.get(occ, {})
        if not data:
            continue
            
        # Check Wage
        wage = data.get("median_annual_wage", 0)
        if isinstance(wage, (int, float)) and range_data["wage"][0] <= wage <= range_data["wage"][1]:
            occ_score += 3
            
        # Check Growth
        growth = data.get("job_outlook_percent", -99)
        if isinstance(growth, (int, float)) and range_data["growth"][0] <= growth <= range_data["growth"][1]:
            occ_score += 3
            
        # Check Jobs
        jobs = data.get("num_jobs", 0)
        if isinstance(jobs, (int, float)) and range_data["jobs"][0] <= jobs <= range_data["jobs"][1]:
            occ_score += 2
            
        # Check Education (Loose string match)
        edu = str(data.get("typical_education", "")).lower()
        if any(term in edu for term in range_data["edu"]):
            occ_score += 2
            
        score += occ_score
        # Only add detail if missed points
        if occ_score < 10:
            feedback.append(f"Data Accuracy: {occ} score {occ_score}/10.")

    if score >= 65: # Threshold for Data Accuracy feedback implies we got points elsewhere
         feedback.append("Data Accuracy: Values plausibly within range.")

    # 5. Summary File (15 pts)
    if result.get("summary_exists") and result.get("summary_fresh"):
        content = result.get("summary_content", "").lower()
        if len(content) > 50:
            score += 10
            feedback.append("Summary: File exists and has content (10/10).")
            # Check for mention of occupations
            mentions = sum(1 for term in ["nurse", "developer", "electrician"] if term in content)
            if mentions >= 2:
                score += 5
                feedback.append("Summary: Mentions target occupations (5/5).")
        else:
             score += 5
             feedback.append("Summary: File exists but content is too short (5/15).")
    else:
        feedback.append("Summary: Missing or not created during task (0/15).")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }