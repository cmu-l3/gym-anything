#!/usr/bin/env python3
"""
Verifier for update_layer_metadata task.
Verifies title, abstract, keywords, and queryable status of a GeoServer layer.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_layer_metadata(traj, env_info, task_info):
    """
    Verify that layer metadata was updated correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_title = metadata.get('expected_title', "World Political Boundaries (1:110m)")
    expected_abstract_phrases = metadata.get('expected_abstract_phrases', ["Natural Earth", "1:110 million"])
    expected_keywords = set(k.lower() for k in metadata.get('expected_keywords', []))
    expected_srs = metadata.get('expected_srs', "EPSG:4326")
    expected_queryable = metadata.get('expected_queryable', True)

    # Copy result file
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

    # Verify nonce integrity
    nonce_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/result_nonce", nonce_temp.name)
        with open(nonce_temp.name, 'r') as f:
            expected_nonce = f.read().strip()
        if result.get('result_nonce') != expected_nonce:
            return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: nonce mismatch"}
    except Exception:
        if result.get('result_nonce'):
            return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: nonce in result but nonce file unreadable"}
    finally:
        if os.path.exists(nonce_temp.name):
            os.unlink(nonce_temp.name)

    # Extract parsed data
    parsed = result.get('parsed_data', {})
    current_title = parsed.get('current_title', '')
    current_abstract = parsed.get('current_abstract', '')
    current_keywords = set(k.lower() for k in parsed.get('current_keywords', []))
    current_srs = parsed.get('current_srs', '')
    current_queryable = parsed.get('current_queryable', False)
    
    initial_title = result.get('initial_title', '')

    score = 0
    feedback_parts = []
    
    # 1. Title Verification (25 points)
    if current_title == expected_title:
        score += 25
        feedback_parts.append("Title updated correctly")
    elif expected_title.lower() in current_title.lower():
        score += 15
        feedback_parts.append(f"Title partially correct ('{current_title}')")
    elif current_title != initial_title and current_title:
        score += 5
        feedback_parts.append(f"Title changed but incorrect ('{current_title}')")
    else:
        feedback_parts.append(f"Title incorrect or unchanged ('{current_title}')")

    # 2. Abstract Verification (25 points)
    abstract_score = 0
    phrases_found = 0
    for phrase in expected_abstract_phrases:
        if phrase.lower() in current_abstract.lower():
            phrases_found += 1
    
    # Scale points based on phrases found
    if len(expected_abstract_phrases) > 0:
        phrase_ratio = phrases_found / len(expected_abstract_phrases)
        if phrase_ratio == 1.0:
            abstract_score = 25
            feedback_parts.append("Abstract contains all required information")
        elif phrase_ratio >= 0.5:
            abstract_score = 15
            feedback_parts.append(f"Abstract contains some required information ({phrases_found}/{len(expected_abstract_phrases)} phrases)")
        elif phrase_ratio > 0:
            abstract_score = 5
            feedback_parts.append("Abstract is missing most required information")
        elif current_abstract and len(current_abstract) > 10:
             # Credit for setting a meaningful abstract even if it misses keywords
             abstract_score = 5
             feedback_parts.append("Abstract set but missing specific keywords")
        else:
             feedback_parts.append("Abstract empty or missing")
    score += abstract_score

    # 3. Keywords Verification (25 points)
    # Check intersection
    found_keywords = expected_keywords.intersection(current_keywords)
    missing_keywords = expected_keywords - current_keywords
    
    if len(expected_keywords) > 0:
        keyword_points_per = 25.0 / len(expected_keywords)
        keyword_score = int(len(found_keywords) * keyword_points_per)
        score += keyword_score
        if len(missing_keywords) == 0:
            feedback_parts.append("All keywords present")
        else:
            feedback_parts.append(f"Missing keywords: {', '.join(missing_keywords)}")
    else:
        score += 25 # No keywords expected

    # 4. Queryable Verification (15 points)
    if current_queryable == expected_queryable:
        score += 15
        feedback_parts.append(f"Queryable status correct ({current_queryable})")
    else:
        feedback_parts.append(f"Queryable status incorrect (expected {expected_queryable}, got {current_queryable})")

    # 5. SRS Integrity (10 points)
    if current_srs == expected_srs:
        score += 10
        feedback_parts.append(f"SRS preserved ({current_srs})")
    else:
        feedback_parts.append(f"SRS incorrect (expected {expected_srs}, got {current_srs})")

    # Anti-gaming: Check if title actually changed from initial
    if current_title == initial_title and score > 0:
        feedback_parts.append("WARNING: Title unchanged from initial state")
        # If they didn't even change the title, it's suspicious if they got other points (maybe the env was already set up?)
        # But we assume clean env.

    # Final logic
    passed = score >= 70 and (current_title == expected_title or expected_title.lower() in current_title.lower())
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }