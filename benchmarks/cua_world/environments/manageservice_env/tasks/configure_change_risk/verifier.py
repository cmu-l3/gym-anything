#!/usr/bin/env python3
"""
Verifier for configure_change_risk task.
Checks if the Risk Assessment questions and choices were correctly created in the database.
"""

import json
import os
import tempfile
import logging
from typing import Dict, List, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_text(text: str) -> str:
    """Normalize text for comparison (lower case, strip whitespace)."""
    if not text:
        return ""
    return text.lower().strip()

def verify_configure_change_risk(traj, env_info, task_info):
    """
    Verify the configuration of Change Management Risk Assessment.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load required configuration from metadata
    metadata = task_info.get('metadata', {})
    required_questions = metadata.get('required_questions', [])

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    found_questions = result.get('found_questions', [])
    app_running = result.get('app_running', False)
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Check Application State (10 pts)
    if app_running:
        score += 10
        feedback_parts.append("ServiceDesk Plus was running")
    else:
        feedback_parts.append("ServiceDesk Plus was NOT running")

    # 2. Check Question Configuration (90 pts)
    # Strategy: For each required question, find the best match in found_questions
    
    total_questions = len(required_questions)
    points_per_question = 90 / total_questions if total_questions > 0 else 0
    
    for req_q in required_questions:
        req_text = normalize_text(req_q['text'])
        match = None
        
        # Find matching question by text
        for found_q in found_questions:
            if req_text in normalize_text(found_q['text']):
                match = found_q
                break
        
        if not match:
            feedback_parts.append(f"Missing question: '{req_q['text']}'")
            continue
            
        # Question found - verify details
        q_score = 0
        q_max = points_per_question
        
        # Base points for creating the question (30% of question points)
        q_score += q_max * 0.3
        
        # Verify description (10% of question points)
        if req_q.get('description') and match.get('description'):
            # Loose matching for description
            req_desc_parts = req_q['description'].split()
            found_desc = normalize_text(match['description'])
            if any(normalize_text(part) in found_desc for part in req_desc_parts if len(part) > 4):
                q_score += q_max * 0.1
        
        # Verify choices and scores (60% of question points)
        req_choices = req_q['choices']
        found_choices = match['choices']
        
        if not req_choices:
            q_score += q_max * 0.6
        elif found_choices:
            # Check each required choice
            choices_matched = 0
            for req_c in req_choices:
                req_c_text = normalize_text(req_c['text'])
                req_c_score = req_c['score']
                
                # Find corresponding choice
                c_match = None
                for fc in found_choices:
                    if req_c_text in normalize_text(fc['text']):
                        c_match = fc
                        break
                
                if c_match:
                    # Choice exists
                    if c_match['score'] == req_c_score:
                        choices_matched += 1
                    else:
                        # Wrong score, partial credit
                        choices_matched += 0.5
                        feedback_parts.append(f"Wrong score for '{req_c['text']}': expected {req_c_score}, got {c_match['score']}")
            
            # Calculate choice score ratio
            choice_ratio = choices_matched / len(req_choices)
            q_score += (q_max * 0.6) * choice_ratio
            
            if choice_ratio < 1.0:
                feedback_parts.append(f"Question '{req_q['text']}' had incomplete/incorrect choices")
            else:
                feedback_parts.append(f"Question '{req_q['text']}' verified")
        else:
            feedback_parts.append(f"Question '{req_q['text']}' has no choices")
            
        score += q_score

    # Final scoring logic
    passed = score >= 80  # High threshold because incorrect risk config is dangerous
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": "; ".join(feedback_parts)
    }