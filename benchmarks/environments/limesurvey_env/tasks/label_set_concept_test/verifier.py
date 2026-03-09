#!/usr/bin/env python3
"""
Verifier for Label Set Concept Test task.

Verifies:
1. Two specific label sets created with correct labels.
2. Concept test survey created with specific title.
3. Survey has two array questions using the scales.
4. Survey is active and anonymized.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_label_set_concept_test(traj, env_info, task_info):
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
    feedback_parts = []
    
    # 1. Anti-Gaming Check (Do Nothing)
    init_s = result.get('initial_survey_count', 0)
    curr_s = result.get('current_survey_count', 0)
    init_l = result.get('initial_labelset_count', 0)
    curr_l = result.get('current_labelset_count', 0)
    
    if curr_s <= init_s and curr_l <= init_l:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No new surveys or label sets created. Task requires creation of both."
        }

    # 2. Verify Satisfaction Label Set (15 pts)
    sat = result.get('satisfaction_labelset', {})
    sat_labels = sat.get('labels', '').lower()
    if sat.get('lid') and sat.get('count', 0) >= 7:
        # Check for key terms
        if 'dissatisfied' in sat_labels and 'satisfied' in sat_labels:
            score += 15
            feedback_parts.append("Satisfaction label set created correctly (15/15)")
        else:
            score += 10
            feedback_parts.append("Satisfaction label set created but missing key text (10/15)")
    elif sat.get('lid'):
        score += 5
        feedback_parts.append(f"Satisfaction label set found but incomplete count: {sat.get('count')} (5/15)")
    else:
        feedback_parts.append("Satisfaction label set NOT found (0/15)")

    # 3. Verify Purchase Intent Label Set (15 pts)
    pi = result.get('purchase_labelset', {})
    pi_labels = pi.get('labels', '').lower()
    if pi.get('lid') and pi.get('count', 0) >= 5:
        if 'buy' in pi_labels:
            score += 15
            feedback_parts.append("Purchase Intent label set created correctly (15/15)")
        else:
            score += 10
            feedback_parts.append("Purchase Intent label set created but missing text (10/15)")
    elif pi.get('lid'):
        score += 5
        feedback_parts.append("Purchase Intent label set incomplete (5/15)")
    else:
        feedback_parts.append("Purchase Intent label set NOT found (0/15)")

    # 4. Verify Survey Title & Existence (10 pts)
    survey = result.get('survey', {})
    title = survey.get('title', '').lower()
    if survey.get('sid'):
        if 'concept test' in title and 'sparkling water' in title:
            score += 10
            feedback_parts.append("Survey created with correct title (10/10)")
        elif 'concept test' in title or 'sparkling water' in title:
            score += 5
            feedback_parts.append("Survey created with partial title match (5/10)")
        else:
            score += 2
            feedback_parts.append("Survey created but title mismatch (2/10)")
    else:
        feedback_parts.append("Survey NOT found (0/10)")

    # 5. Verify Survey Structure (Active/Anon/Groups) (25 pts)
    if survey.get('sid'):
        # Active (15)
        if survey.get('active', 'N') == 'Y':
            score += 15
            feedback_parts.append("Survey active (15/15)")
        else:
            feedback_parts.append("Survey NOT active (0/15)")
        
        # Anonymized (5)
        if survey.get('anonymized', 'N') == 'Y':
            score += 5
            feedback_parts.append("Survey anonymized (5/5)")
            
        # Groups (5)
        if survey.get('group_count', 0) >= 2:
            score += 5
            feedback_parts.append("Question groups correct (5/5)")
            
    # 6. Verify Questions (30 pts)
    qs = result.get('questions', {})
    
    # Appeal Question (15)
    if qs.get('appeal_found'):
        subq = qs.get('appeal_subq_count', 0)
        answers = qs.get('appeal_answers', '').lower()
        if subq >= 6 and ('dissatisfied' in answers or 'satisfied' in answers):
            score += 15
            feedback_parts.append("Product Appeal array question correct (15/15)")
        elif subq >= 1:
            score += 8
            feedback_parts.append("Product Appeal array question partial (8/15)")
    else:
        feedback_parts.append("Product Appeal question missing (0/15)")
        
    # Purchase Question (15)
    if qs.get('purchase_found'):
        subq = qs.get('purchase_subq_count', 0)
        answers = qs.get('purchase_answers', '').lower()
        if subq >= 4 and 'buy' in answers:
            score += 15
            feedback_parts.append("Purchase Intent array question correct (15/15)")
        elif subq >= 1:
            score += 8
            feedback_parts.append("Purchase Intent array question partial (8/15)")
    else:
        feedback_parts.append("Purchase Intent question missing (0/15)")

    # 7. VLM Trajectory Verification (Optional Bonus/Confirmation)
    # We only deduct if score is high but VLM sees nothing
    if score > 50:
        frames = sample_trajectory_frames(traj, n=5)
        vlm_res = query_vlm(
            images=frames, 
            prompt="Does this sequence show a user interacting with LimeSurvey interface, creating label sets or editing survey questions? Return JSON with 'valid_interaction': boolean."
        )
        if vlm_res.get('success'):
            if not vlm_res['parsed'].get('valid_interaction', False):
                feedback_parts.append("(VLM Warning: Trajectory didn't show clear interaction)")
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }