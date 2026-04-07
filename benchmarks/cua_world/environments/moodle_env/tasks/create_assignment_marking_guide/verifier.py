#!/usr/bin/env python3
"""Verifier for Create Assignment Marking Guide task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_assignment_marking_guide(traj, env_info, task_info):
    """
    Verify configuration of Marking Guide.
    
    Criteria:
    1. Assignment uses 'guide' method (15 pts)
    2. Guide name matches (10 pts)
    3. Guide status is Ready (20) (10 pts)
    4. Criterion 1 (Argument) exists with correct score and marker text (15 pts)
    5. Criterion 2 (Analysis) exists with correct score and marker text (15 pts)
    6. Criterion 3 (Formatting) exists with correct score and marker text (15 pts)
    7. Frequently used comments exist (at least 2) (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/marking_guide_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
            
        score = 0
        feedback_parts = []
        
        # 1. Check Grading Method
        method = result.get('grading_method', '')
        if method == 'guide':
            score += 15
            feedback_parts.append("Grading method set to Marking Guide")
        else:
            feedback_parts.append(f"Grading method mismatch: {method}")
            
        # 2. Check Guide Name
        guide_name = result.get('guide_name', '')
        expected_guide_name = metadata.get('guide_name', 'Research Paper Standard Guide')
        if expected_guide_name.lower() in guide_name.lower():
            score += 10
            feedback_parts.append("Guide name matches")
        else:
            feedback_parts.append(f"Guide name mismatch: '{guide_name}'")
            
        # 3. Check Guide Status
        # 0=Draft, 20=Ready
        status = result.get('guide_status', 0)
        if status == 20:
            score += 10
            feedback_parts.append("Guide status is Ready")
        else:
            feedback_parts.append(f"Guide status is Draft/Not Ready ({status})")
            
        # 4-6. Check Criteria
        criteria = result.get('criteria', [])
        expected_criteria = metadata.get('criteria', [])
        
        criteria_score = 0
        criteria_feedback = []
        
        for exp in expected_criteria:
            exp_name = exp['name']
            exp_score = exp['maxscore']
            exp_desc_part = exp['marker_desc_contains'].lower()
            
            # Find matching criterion
            match = None
            for c in criteria:
                if exp_name.lower() in c.get('shortname', '').lower():
                    match = c
                    break
            
            if match:
                # Check score
                if abs(float(match.get('maxscore', 0)) - exp_score) < 0.1:
                    # Check marker description
                    if exp_desc_part in match.get('descriptionmarkers', '').lower():
                        criteria_score += 15
                        criteria_feedback.append(f"Criterion '{exp_name}' correct")
                    else:
                        criteria_score += 10 # Partial for name+score but wrong desc
                        criteria_feedback.append(f"Criterion '{exp_name}' marker description missing keywords")
                else:
                    criteria_score += 5 # Partial for name only
                    criteria_feedback.append(f"Criterion '{exp_name}' score incorrect")
            else:
                criteria_feedback.append(f"Criterion '{exp_name}' missing")
                
        score += criteria_score
        feedback_parts.extend(criteria_feedback)
        
        # 7. Check Comments
        comments = result.get('comments', [])
        if len(comments) >= 2:
            score += 20
            feedback_parts.append(f"Found {len(comments)} frequently used comments")
        elif len(comments) == 1:
            score += 10
            feedback_parts.append("Found 1 frequently used comment (expected 2)")
        else:
            feedback_parts.append("No frequently used comments found")
            
        return {
            "passed": score >= 70,
            "score": min(score, 100),
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification failed: {str(e)}"}