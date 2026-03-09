#!/usr/bin/env python3
"""
Verifier for dot_flight_rights_audit task.
Checks:
1. Browser History (DOT.gov visits)
2. Bookmark Organization (Folder + Links)
3. Downloaded Artifacts (PDF Guide)
4. JSON Data Accuracy (Airline Commitments)
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_dot_flight_rights_audit(traj, env_info, task_info):
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Scoring Logic
    score = 0
    feedback = []
    
    # --- Criterion 1: DOT Visits (10 pts) ---
    visits = result.get('dot_visits', 0)
    if visits > 0:
        score += 10
        feedback.append(f"Visited DOT website ({visits} times).")
    else:
        feedback.append("Did not visit transportation.gov.")

    # --- Criterion 2: Bookmarks (15 pts) ---
    # Folder exists (5) + Items >= 2 (10)
    if result.get('folder_exists', False):
        score += 5
        count = result.get('bookmarks_in_folder', 0)
        if count >= 2:
            score += 10
            feedback.append(f"Created 'Travel Policy Resources' folder with {count} bookmarks.")
        else:
            feedback.append(f"Created folder but only found {count} bookmarks (expected >= 2).")
    else:
        feedback.append("Did not create 'Travel Policy Resources' bookmark folder.")

    # --- Criterion 3: PDF Download (15 pts) ---
    if result.get('pdf_found', False):
        score += 15
        feedback.append(f"Downloaded valid PDF guide: {result.get('pdf_name')}")
    else:
        feedback.append("Did not download a PDF guide > 50KB.")

    # --- Criterion 4: JSON File Existence (10 pts) ---
    json_data = result.get('json_data')
    if result.get('json_exists') and result.get('json_fresh') and json_data:
        score += 10
        feedback.append("Audit JSON file created successfully.")
    else:
        feedback.append("Audit JSON file missing, stale, or invalid.")
        # If file is invalid, we can't check content, so return early
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    # --- Criterion 5: Data Accuracy (50 pts) ---
    # We check for the presence of the 4 airlines and key commitments.
    # Note: Commitments change, but "Spirit" vs "Delta" is a strong discriminator.
    # Spirit usually has NO interline rebook. Delta/American usually DO.
    
    # Structure check (10 pts)
    airlines = ["American", "Delta", "Southwest", "Spirit"]
    found_airlines = 0
    
    # Normalize keys for case-insensitive matching if needed, 
    # but the instructions asked for specific keys. 
    # We'll assume the agent follows instructions on structure.
    
    # Helper to find airline dict regardless of exact key casing
    def get_airline_data(name, data):
        for k, v in data.items():
            if name.lower() in k.lower():
                return v
        # Maybe nested under "airlines" key?
        if "airlines" in data:
            for k, v in data["airlines"].items():
                if name.lower() in k.lower():
                    return v
        return None

    data_points = 0
    
    # Check each airline
    for airline in airlines:
        adata = get_airline_data(airline, json_data)
        if adata:
            found_airlines += 1
            # Check for required boolean keys
            if all(k in adata for k in ["meal_voucher", "hotel_accommodation", "rebook_partner"]):
                data_points += 5 # 5 pts per airline for valid structure
                
                # FACTUAL CHECK (5 pts per airline)
                # We apply a loose heuristic based on persistent policies to avoid breaking on small updates
                # but catch hallucinations (e.g. Spirit having same rights as Delta).
                
                # Rule 1: Spirit/Frontier generally do NOT rebook on partners (Interline).
                if airline == "Spirit":
                    # If they claim Spirit rebooks on partner, that's likely wrong/hallucination
                    if adata.get("rebook_partner") is False: 
                        data_points += 5
                    else:
                        feedback.append("Inaccurate: Spirit typically does not rebook on partner airlines.")
                
                # Rule 2: Delta/American generally DO rebook on partners.
                elif airline in ["Delta", "American"]:
                    if adata.get("rebook_partner") is True:
                        data_points += 5
                    else:
                        feedback.append(f"Inaccurate: {airline} typically commits to partner rebooking.")
                
                # Rule 3: Southwest usually does NOT rebook on partners (no interline).
                elif airline == "Southwest":
                    if adata.get("rebook_partner") is False:
                        data_points += 5
                    else:
                        feedback.append("Inaccurate: Southwest typically does not rebook on partner airlines.")

            else:
                feedback.append(f"Missing required keys for {airline}.")
        else:
            feedback.append(f"Missing data for {airline}.")

    score += data_points

    # 4. Final Verification
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }