#!/usr/bin/env python3
import json
import os
import tempfile
from fuzzywuzzy import fuzz  # Standard in the environment usually, or use simple string matching

def verify_catalog_legal_cases(traj, env_info, task_info):
    """
    Verify that 3 specific legal cases were created with correct metadata.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if "error" in result_data:
        return {"passed": False, "score": 0, "feedback": f"Database error: {result_data['error']}"}

    created_cases = result_data.get("created_cases", [])
    targets = task_info.get("metadata", {}).get("targets", [])
    
    score = 0
    feedback = []
    
    # Check if we created enough cases (Item Creation Score)
    # Max 15 points for creating 3 case items (5 each)
    case_count = len(created_cases)
    creation_score = min(case_count * 5, 15)
    score += creation_score
    if case_count == 0:
        feedback.append("No new Case items found.")
    else:
        feedback.append(f"Found {case_count} new Case items.")

    # Match targets to created cases
    # Strategy: For each target, find the best matching created case by title
    # Then score that match on other fields
    
    used_indices = set()
    
    for target in targets:
        target_title = target['title']
        best_match_idx = -1
        best_match_ratio = 0
        
        # Find best match by title
        for idx, case in enumerate(created_cases):
            if idx in used_indices:
                continue
            
            case_title = case['fields'].get('title') or ""
            ratio = fuzz.ratio(target_title.lower(), case_title.lower())
            
            if ratio > best_match_ratio:
                best_match_ratio = ratio
                best_match_idx = idx
        
        target_score = 0
        target_feedback = []
        
        # Threshold for accepting a match (relaxed to allow minor typos in title)
        if best_match_ratio > 80:
            used_indices.add(best_match_idx)
            matched_case = created_cases[best_match_idx]['fields']
            
            # Title Score (5 pts)
            if best_match_ratio == 100:
                target_score += 5
            else:
                target_score += 3 # Minor typo
                
            # Check other fields
            # Fields to check: court(5), date(5), docket(5), reporter/vol/page(10 combined)
            
            # Court (5 pts)
            act_court = matched_case.get('court') or ""
            if fuzz.partial_ratio(target['court'].lower(), act_court.lower()) > 90:
                target_score += 5
            else:
                target_feedback.append(f"Court mismatch (expected '{target['court']}', got '{act_court}')")

            # Docket (5 pts)
            # Normalize: remove spaces
            exp_docket = target['docket'].replace(" ", "")
            act_docket = (matched_case.get('docketNumber') or "").replace(" ", "")
            if exp_docket.lower() == act_docket.lower():
                target_score += 5
            else:
                target_feedback.append(f"Docket mismatch (expected '{target['docket']}', got '{matched_case.get('docketNumber')}')")
                
            # Date (5 pts) - Just check year for simplicity if full date matches hard
            exp_date = target['date']
            act_date = matched_case.get('date') or ""
            if exp_date in act_date:
                target_score += 5
            else:
                target_feedback.append(f"Date mismatch (expected '{exp_date}', got '{act_date}')")
                
            # Reporter Details (10 pts total)
            # Reporter (4), Volume (3), Page (3)
            rep_score = 0
            if target['reporter'] == matched_case.get('reporter'): rep_score += 4
            if target['volume'] == matched_case.get('reporterVolume'): rep_score += 3
            if target['page'] == matched_case.get('firstPage'): rep_score += 3
            
            if rep_score < 10:
                target_feedback.append("Reporter citation details incomplete/incorrect")
            target_score += rep_score
            
            feedback.append(f"Case '{target_title}': {target_score}/30 pts. " + "; ".join(target_feedback))
            score += target_score
            
        else:
            feedback.append(f"Case '{target_title}' NOT found.")
            
    # Normalize score?
    # Max points: 
    # Creation: 15
    # Per case: 30 (Title 5 + Court 5 + Date 5 + Docket 5 + Citation 10) * 3 = 90?
    # Wait, the scoring logic in README said 100 total.
    # README:
    # Creation: 15 (Implicitly handled if we have 3 matches? Let's keep creation separate)
    # 3 Cases * (Title 5 + Court 5 + Docket 5 + Citation 10) = 3 * 25 = 75
    # Missing Date in README table? README said "Date field contains year". Let's verify README.
    # README Table:
    # Item Creation: 15
    # Google v Oracle: Title(5)+Court(5)+Docket(5)+Reporter(10) = 25.
    # Total = 15 + 25*3 = 90.
    # My code adds Date (5) -> 30 per case.
    # Total = 15 + 30*3 = 105.
    # Let's cap at 100.
    
    score = min(score, 100)
    
    # Pass threshold 80
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }