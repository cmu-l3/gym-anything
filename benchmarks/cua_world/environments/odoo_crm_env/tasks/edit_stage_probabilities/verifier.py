#!/usr/bin/env python3
"""
Verifier for edit_stage_probabilities task.

Checks:
1. Probability values in database match expected.
2. Requirements text contains key phrases.
3. Records were modified AFTER task start time (anti-gaming).
4. VLM verifies UI interaction via trajectory.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

# Import VLM utils from framework
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_edit_stage_probabilities(traj, env_info, task_info):
    """
    Verifies that CRM stages were updated correctly.
    """
    # 1. Setup - Get data from container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if 'error' in result_data:
        return {"passed": False, "score": 0, "feedback": f"Error during data export: {result_data['error']}"}

    # 2. Parse Expected Metadata
    metadata = task_info.get('metadata', {}).get('stages', {})
    
    # 3. Analyze Data
    stages_data = result_data.get('stages', [])
    task_start_iso = result_data.get('task_start_iso', '')
    
    # Convert ISO strings to datetime objects for comparison
    try:
        # Odoo returns UTC times usually
        # Format example: "2023-10-27 10:00:00"
        task_start_dt = datetime.fromisoformat(task_start_iso)
    except ValueError:
        # Fallback if format is slightly off (e.g. no T separator)
        task_start_dt = datetime.strptime(task_start_iso, "%Y-%m-%d %H:%M:%S")

    score = 0
    feedback_parts = []
    stages_found = 0
    stages_modified = 0
    
    # Map stages by name for easy lookup
    stages_map = {s['name']: s for s in stages_data}

    for stage_name, criteria in metadata.items():
        if stage_name not in stages_map:
            feedback_parts.append(f"Stage '{stage_name}' not found in database.")
            continue
        
        stages_found += 1
        actual = stages_map[stage_name]
        
        # Check Modification Time (Anti-Gaming)
        write_date_str = actual.get('write_date', '')
        is_modified = False
        if write_date_str:
            try:
                # Odoo write_date is typically UTC without TZ info in the string from XMLRPC
                write_dt = datetime.fromisoformat(write_date_str)
                # Allow a small buffer (e.g. 1 sec) or strictly greater
                if write_dt >= task_start_dt:
                    is_modified = True
                    stages_modified += 1
            except Exception:
                pass # Date parsing fail, assume not modified

        # Scoring: Probability (10 pts)
        expected_prob = criteria['expected_prob']
        actual_prob = actual.get('probability', 0.0)
        
        # Allow small float tolerance
        if abs(actual_prob - expected_prob) < 0.1:
            score += 10
            feedback_parts.append(f"✓ {stage_name}: Probability correct ({actual_prob}%)")
        else:
            feedback_parts.append(f"✗ {stage_name}: Probability mismatch (Found {actual_prob}%, Expected {expected_prob}%)")

        # Scoring: Requirements Text (10 pts)
        req_text = str(actual.get('requirements', '') or '')
        expected_phrases = criteria['required_text']
        
        phrases_found = [p for p in expected_phrases if p.lower() in req_text.lower()]
        
        if len(phrases_found) == len(expected_phrases):
            score += 10
            feedback_parts.append(f"✓ {stage_name}: Requirements correct")
        elif len(phrases_found) > 0:
            score += 5 # Partial credit
            feedback_parts.append(f"~ {stage_name}: Requirements partial match")
        else:
            feedback_parts.append(f"✗ {stage_name}: Requirements missing/incorrect")

    # Scoring: Modification Check (10 pts)
    # At least 3 stages must show a write_date after task start
    if stages_modified >= 3:
        score += 10
        feedback_parts.append(f"✓ Anti-gaming passed: {stages_modified} stages modified during task")
    else:
        feedback_parts.append(f"✗ Anti-gaming failed: Only {stages_modified} stages modified (DB timestamps old)")

    # 4. VLM Verification (Trajectory Check) (10 pts)
    # We want to see the "Edit Stage" modal or the settings menu being clicked
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=8)
        
        prompt = """
        Review these screenshots of a user interacting with Odoo CRM.
        I am looking for evidence that the user is editing pipeline stages.
        
        Look for:
        1. Clicking the gear icon on a Kanban column header.
        2. A modal dialog titled "Open: [Stage Name]" or similar stage editing form.
        3. Editing the "Probability" or "Requirements" fields.
        
        Did the user perform these actions? Return TRUE only if there is visual evidence of editing stage settings.
        """
        
        vlm_result = query_vlm(images=frames, prompt=prompt).get('parsed', {})
        
        # Simple boolean check from VLM, could be more complex
        if vlm_result.get('answer', False) is True or "yes" in str(vlm_result.get('response', '')).lower():
            vlm_score = 10
            feedback_parts.append("✓ VLM: Visual evidence of stage editing found")
        else:
            feedback_parts.append("? VLM: No clear visual evidence of stage editing modal")
            
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Default to pass VLM if programmatic passes perfectly, to avoid false negatives on flaky VLM
        if score >= 80: 
            vlm_score = 10
    
    score += vlm_score

    # Final Pass Determination
    # Threshold: 60 points + Must have modified DB
    passed = (score >= 60) and (stages_modified >= 1)

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }