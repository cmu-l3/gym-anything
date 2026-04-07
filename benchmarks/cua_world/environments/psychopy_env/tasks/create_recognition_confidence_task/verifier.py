#!/usr/bin/env python3
"""
Verifier for create_recognition_confidence_task.

Verification Strategy:
1. File Existence & Modification (20 pts)
2. CSV Data Integrity (30 pts)
   - Study list has correct words
   - Test list has old/new words and correct answer mapping
3. Experiment Structure (20 pts)
   - Correct routines (Study, Distractor, Test, Confidence)
   - Slider component present
4. Conditional Logic (30 pts) (CRITICAL)
   - Code component exists
   - Contains 'continueRoutine = False' inside a conditional block

Pass threshold: 70 pts AND Logic must be present.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_recognition_confidence_task(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    study_words_expected = set([w.lower() for w in metadata.get('study_words', [])])
    test_foils_expected = set([w.lower() for w in metadata.get('test_foils', [])])
    
    feedback_parts = []
    score = 0
    
    # Load result
    result = {}
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_path = tmp.name
        copy_from_env("/tmp/recognition_confidence_result.json", tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}
    finally:
        if 'tmp_path' in locals() and os.path.exists(tmp_path):
            os.unlink(tmp_path)

    # 1. Files (20 pts)
    if result.get('exp_file_exists') and result.get('study_csv_exists') and result.get('test_csv_exists'):
        score += 15
        feedback_parts.append("All required files created.")
        if result.get('files_modified_during_task'):
            score += 5
            feedback_parts.append("Files modified during task.")
    else:
        feedback_parts.append("Missing one or more required files.")

    # 2. CSV Data (30 pts)
    # Check Study List
    found_study = set([w.lower() for w in result.get('study_words_found', [])])
    if study_words_expected.issubset(found_study):
        score += 10
        feedback_parts.append("Study list contains correct words.")
    else:
        feedback_parts.append(f"Study list missing words. Found: {list(found_study)}")

    # Check Test List columns and rows
    if result.get('has_correct_ans_col') and result.get('test_words_count') >= 10:
        score += 10
        feedback_parts.append("Test list has correct columns and row count.")
    else:
        feedback_parts.append("Test list missing 'corrAns' or has too few rows.")
        
    if result.get('test_mapping_correct'):
        score += 10
        feedback_parts.append("Test list response mapping (old=y, new=n) is correct.")

    # 3. Experiment Structure (20 pts)
    routines = [r.lower() for r in result.get('routines', [])]
    # Look for partial matches in routine names
    has_study = any('study' in r for r in routines)
    has_test = any('trial' in r or 'recog' in r for r in routines)
    has_conf = any('conf' in r or 'rating' in r for r in routines)
    
    if has_study and has_test and has_conf:
        score += 10
        feedback_parts.append("Experiment flow contains required phases.")
    
    if result.get('has_slider'):
        score += 10
        feedback_parts.append("Slider component found.")
    else:
        feedback_parts.append("Slider component missing.")

    # 4. Conditional Logic (30 pts)
    if result.get('has_code_component'):
        score += 10
        if result.get('code_logic_found'):
            score += 20
            feedback_parts.append("Conditional logic (continueRoutine = False) found.")
        else:
            feedback_parts.append("Code component found but missing 'continueRoutine = False' logic.")
            # Verify snippet manually if close
            snippet = result.get('logic_snippet', '')
            logger.info(f"Logic snippet: {snippet}")
    else:
        feedback_parts.append("No Code component found.")

    # Pass Condition
    passed = score >= 70 and result.get('code_logic_found', False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }