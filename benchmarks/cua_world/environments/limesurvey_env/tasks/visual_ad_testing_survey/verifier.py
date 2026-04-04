#!/usr/bin/env python3
"""
Verifier for visual_ad_testing_survey task.

Criteria:
1. Survey exists with correct title.
2. Two questions (C1, C2) exist.
3. Images (concept_vibrant.png, concept_minimalist.png) are uploaded to the survey directory.
4. Question text contains HTML <img> tags referencing the uploads.
5. Survey is active.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_visual_ad_testing(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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
    
    # 1. Survey Exists (10 pts)
    if result.get('survey_found'):
        score += 10
        feedback.append("Survey found")
    else:
        return {"passed": False, "score": 0, "feedback": "Survey 'Beverage Packaging Concept Test 2025' not found"}

    # 2. Survey Active (10 pts)
    if result.get('active') == 'Y':
        score += 10
        feedback.append("Survey is active")
    else:
        feedback.append("Survey is NOT active")

    # 3. Check Uploaded Files (30 pts)
    uploaded_files = result.get('uploaded_files', [])
    # Allow for some renaming by LimeSurvey (e.g., random chars added), but should contain original name
    has_vibrant = any('vibrant' in f.lower() for f in uploaded_files)
    has_minimalist = any('minimalist' in f.lower() for f in uploaded_files)
    
    if has_vibrant:
        score += 15
        feedback.append("Vibrant concept image uploaded")
    else:
        feedback.append("Vibrant concept image NOT found in survey upload directory")
        
    if has_minimalist:
        score += 15
        feedback.append("Minimalist concept image uploaded")
    else:
        feedback.append("Minimalist concept image NOT found in survey upload directory")

    # 4. Check Questions Content (50 pts)
    questions = result.get('questions', [])
    c1_found = False
    c2_found = False
    c1_has_img = False
    c2_has_img = False
    
    for q in questions:
        code = q.get('code', '').upper()
        text = q.get('text', '').lower()
        qtype = q.get('type', '')
        
        # Check C1
        if code == 'C1':
            c1_found = True
            if '<img' in text and 'vibrant' in text:
                c1_has_img = True
            # Check type (5-point choice is '5', List is 'L')
            if qtype in ['5', 'L']: 
                score += 5 # Bonus for correct type
            
        # Check C2
        if code == 'C2':
            c2_found = True
            if '<img' in text and 'minimalist' in text:
                c2_has_img = True
            if qtype in ['5', 'L']:
                score += 5

    if c1_found and c2_found:
        score += 10
        feedback.append("Both question codes found")
    else:
        feedback.append("Missing question codes C1 or C2")

    if c1_has_img:
        score += 15
        feedback.append("C1 embeds vibrant image")
    else:
        feedback.append("C1 does not embed the vibrant image correctly")

    if c2_has_img:
        score += 15
        feedback.append("C2 embeds minimalist image")
    else:
        feedback.append("C2 does not embed the minimalist image correctly")

    passed = score >= 85
    return {
        "passed": passed,
        "score": score,
        "feedback": ". ".join(feedback)
    }