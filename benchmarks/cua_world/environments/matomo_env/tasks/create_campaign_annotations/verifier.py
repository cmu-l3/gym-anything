#!/usr/bin/env python3
"""
Verifier for Create Campaign Annotations task.

Task: Create 3 specific annotations on Site ID 1.
1. 2025-03-17: "Spring Promo..." (Starred)
2. 2025-04-01: "Email Blast..." (Not Starred)
3. 2025-04-14: "Homepage Redesign..." (Not Starred)

Scoring:
- 10 pts: Any interaction (count > initial)
- 35 pts: Annotation 1 correct (Date + Text + Star)
- 20 pts: Annotation 2 correct (Date + Text)
- 20 pts: Annotation 3 correct (Date + Text)
- 15 pts: Bonus for all 3 perfect

Pass Threshold: 60 pts
"""

import json
import logging
import os
import tempfile
from typing import Dict, Any, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_text(s: str) -> str:
    return s.strip().lower() if s else ""

def verify_create_campaign_annotations(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_list = metadata.get('annotations', [])

    # Retrieve result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/create_campaign_annotations_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    actual_annotations = result.get('annotations', [])
    initial_count = result.get('initial_count', 0)
    current_count = result.get('current_count', 0)

    score = 0
    feedback = []
    
    # 1. Check for basic interaction (10 pts)
    # Since we cleared annotations in setup, initial_count should be 0, but logic holds.
    if current_count > initial_count:
        score += 10
        feedback.append("New annotations detected (+10)")
    else:
        feedback.append("No new annotations created.")
        return {"passed": False, "score": 0, "feedback": "No annotations created"}

    # 2. Verify specific annotations
    # We look for a match for each expected annotation in the actual list.
    matches_found = 0
    
    for i, exp in enumerate(expected_list):
        exp_date = exp['date']
        exp_pattern = normalize_text(exp['text_pattern'])
        exp_starred = exp['starred']
        
        # Find best match in actuals
        match = None
        for act in actual_annotations:
            act_date = act.get('date', '')
            act_note = normalize_text(act.get('note', ''))
            
            # Check date and text pattern
            if act_date == exp_date and exp_pattern in act_note:
                match = act
                break
        
        if match:
            # Base points for date+text match
            # Weighting: 1st is 25 (base) + 10 (star check) = 35 total logic below
            # 2nd/3rd are 20 total
            
            pts = 0
            item_feedback = ""
            
            if i == 0: # Spring Promo (needs star)
                act_starred = str(match.get('starred', '0')) in ['1', 'true']
                if act_starred == exp_starred:
                    pts = 35
                    item_feedback = f"Annotation '{exp_pattern}' correct with Star (+35)"
                else:
                    pts = 20
                    item_feedback = f"Annotation '{exp_pattern}' found but wrong star status (+20)"
            else: # Others (20 pts)
                pts = 20
                item_feedback = f"Annotation '{exp_pattern}' correct (+20)"
            
            score += pts
            matches_found += 1
            feedback.append(item_feedback)
        else:
            feedback.append(f"Missing or incorrect: {exp_pattern} on {exp_date}")

    # 3. Bonus for perfection (15 pts)
    # Requires all 3 matches found and score reflects full points so far (10 + 35 + 20 + 20 = 85)
    if matches_found == 3 and score == 85:
        score += 15
        feedback.append("All annotations perfect (+15 Bonus)")

    passed = score >= 60

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "details": {
            "initial_count": initial_count,
            "current_count": current_count,
            "actual_annotations": actual_annotations
        }
    }