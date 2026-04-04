#!/usr/bin/env python3
"""
Verifier for populate_curated_playlist task.

Checks:
1. Playlist 'Epic Rock' exists.
2. Playlist contains correct tracks based on:
   - Genre = 'Rock'
   - Duration > 5 mins
   - Composer IS NOT NULL
3. Precision and Recall of the track list.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_populate_curated_playlist(traj, env_info, task_info):
    """
    Verify the playlist creation and population.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Extract analysis
    analysis = result.get('analysis', {})
    if 'error' in analysis:
        return {"passed": False, "score": 0, "feedback": f"Analysis failed: {analysis['error']}"}

    file_modified = result.get('file_modified', False)
    playlist_found = analysis.get('playlist_found', False)
    playlist_name = analysis.get('playlist_name', 'None')
    
    tp = analysis.get('true_positives', 0)
    fp = analysis.get('false_positives', 0)
    fn = analysis.get('false_negatives', 0)
    gt_count = analysis.get('ground_truth_count', 0)
    agent_count = analysis.get('agent_count', 0)

    feedback_parts = []
    score = 0

    # Criterion 1: File Modified (Pre-requisite)
    if not file_modified:
        return {"passed": False, "score": 0, "feedback": "Database file was not saved/modified."}
    
    score += 10
    feedback_parts.append("Database saved")

    # Criterion 2: Playlist Created (20 pts)
    if playlist_found:
        score += 20
        feedback_parts.append(f"Playlist '{playlist_name}' found")
    else:
        feedback_parts.append("Playlist 'Epic Rock' NOT found")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Criterion 3: Content Accuracy (70 pts split)
    # Full points if sets match exactly (TP=GT, FP=0)
    
    # Calculate Jaccard similarity or F1? 
    # Let's use simple deduction points.
    
    if gt_count == 0:
        # Should not happen with Chinook DB
        feedback_parts.append("Error: No qualifying tracks found in Ground Truth")
    else:
        # Recall (did we get all needed tracks?)
        recall = tp / gt_count if gt_count > 0 else 0
        recall_score = int(recall * 35)
        score += recall_score
        
        # Precision (did we avoid bad tracks?)
        precision = tp / agent_count if agent_count > 0 else 0
        precision_score = int(precision * 35)
        score += precision_score
        
        feedback_parts.append(f"Tracks: {agent_count} added (Target: {gt_count})")
        feedback_parts.append(f"Correct: {tp}, Missing: {fn}, Extra/Wrong: {fp}")

    passed = (score >= 95)  # Require near perfection for SQL tasks

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "true_positives": tp,
            "false_positives": fp,
            "false_negatives": fn
        }
    }