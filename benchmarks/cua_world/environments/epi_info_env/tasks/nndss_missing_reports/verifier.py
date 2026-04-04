#!/usr/bin/env python3
"""
Verifier for NNDSS Missing Reports Task.
Evaluates if the agent correctly identified the non-reporting jurisdictions.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_nndss_missing_reports(traj, env_info, task_info):
    """
    Verify the NNDSS missing reports task.
    """
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    ground_truth = set([s.lower() for s in metadata.get('missing_states_ground_truth', [])])
    
    # 2. Retrieve Result JSON from Container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: Windows path in container mapped to local temp
        copy_from_env("C:\\Windows\\Temp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Analyze Results
    score = 0
    feedback = []

    # Criterion 1: Output File Exists (10 pts)
    if result.get('output_exists'):
        score += 10
        feedback.append("Output file exists.")
    else:
        feedback.append("Output file missing.")
        return {"passed": False, "score": 0, "feedback": "Output file not found."}

    # Criterion 2: File Created During Task (10 pts)
    if result.get('file_created_during_task'):
        score += 10
    else:
        feedback.append("Warning: File timestamp indicates it wasn't created during this session.")

    # Criterion 3: Project Created (10 pts)
    if result.get('project_created'):
        score += 10
        feedback.append("Epi Info project created.")
    else:
        feedback.append("Epi Info project file not found.")

    # Criterion 4: Content Accuracy (70 pts)
    content = result.get('output_content', '')
    
    # Clean and parse lines
    lines = [line.strip().lower() for line in content.splitlines() if line.strip()]
    agent_set = set(lines)
    
    # Calculate metrics
    true_positives = ground_truth.intersection(agent_set)
    false_positives = agent_set - ground_truth
    false_negatives = ground_truth - agent_set
    
    # Scoring logic for content
    # Start with 70 pts for content
    # Deduct 10 pts for each false negative (missing a state)
    # Deduct 5 pts for each false positive (listing a state that reported)
    
    content_score = 70
    
    if len(false_negatives) > 0:
        deduction = len(false_negatives) * 10
        content_score -= deduction
        feedback.append(f"Missed states: {', '.join([s.title() for s in false_negatives])}")
        
    if len(false_positives) > 0:
        deduction = len(false_positives) * 5
        content_score -= deduction
        feedback.append(f"Incorrectly listed: {', '.join([s.title() for s in false_positives])}")
    
    if content_score < 0:
        content_score = 0
        
    score += content_score
    
    if len(false_negatives) == 0 and len(false_positives) == 0:
        feedback.append("Perfect identification of missing jurisdictions.")

    # Pass Threshold
    passed = score >= 70 and len(false_negatives) <= 1
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }