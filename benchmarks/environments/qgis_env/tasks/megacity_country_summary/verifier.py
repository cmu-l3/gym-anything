#!/usr/bin/env python3
"""
Verifier for megacity_country_summary task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_megacity_country_summary(traj, env_info, task_info):
    """
    Verify that the agent correctly summarized megacity statistics by country.

    Scoring (100 points):
    - Output file exists and is valid GeoJSON: 20 points
    - Output preserves original country features (~177): 10 points
    - Count of megacities matches ground truth for key countries: 35 points
    - Sum of population matches ground truth for key countries: 35 points

    Pass threshold: 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    logger.info(f"Task result: {result}")

    score = 0
    feedback_parts = []
    
    analysis = result.get('analysis', {})
    
    # 1. File Existence & Validity (20 pts)
    if result.get('file_exists', False) and analysis.get('is_geojson', False):
        score += 20
        feedback_parts.append("Valid GeoJSON output found")
    elif result.get('file_exists', False):
        score += 10
        feedback_parts.append("Output file exists but might be invalid format")
    else:
        feedback_parts.append("Output file not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Feature Count Preservation (10 pts)
    # Natural Earth admin 0 has approx 177 countries. 
    feat_count = analysis.get('feature_count', 0)
    if 150 <= feat_count <= 200:
        score += 10
        feedback_parts.append(f"Feature count normal ({feat_count})")
    else:
        feedback_parts.append(f"Unexpected feature count: {feat_count} (expected ~177)")

    # 3. Accuracy Check (70 pts total)
    countries_checked = analysis.get('countries_checked', [])
    if not countries_checked:
        feedback_parts.append("Could not verify statistics (analysis failed)")
    else:
        total_checks = len(countries_checked)
        count_correct = sum(1 for c in countries_checked if c.get('count_ok'))
        sum_correct = sum(1 for c in countries_checked if c.get('sum_ok'))
        
        # Calculate scores
        # 35 points for counts
        count_score = int((count_correct / total_checks) * 35)
        score += count_score
        
        # 35 points for sums
        sum_score = int((sum_correct / total_checks) * 35)
        score += sum_score
        
        feedback_parts.append(f"Megacity counts correct for {count_correct}/{total_checks} countries")
        feedback_parts.append(f"Population sums correct for {sum_correct}/{total_checks} countries")
        
        # Detailed feedback for failures
        failures = [c['name'] for c in countries_checked if not c.get('count_ok')]
        if failures:
            feedback_parts.append(f"Count mismatch in: {', '.join(failures[:3])}")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }