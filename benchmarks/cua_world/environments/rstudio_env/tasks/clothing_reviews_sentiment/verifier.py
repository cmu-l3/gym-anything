#!/usr/bin/env python3
"""
Verifier for Clothing Reviews Sentiment Analysis Task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sentiment_analysis(traj, env_info, task_info):
    """
    Verify the RStudio sentiment analysis task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    score = 0
    feedback_parts = []
    
    # 1. Summary CSV (40 points)
    if result.get('summary_exists') and result.get('summary_new'):
        score += 10
        feedback_parts.append("Summary CSV created (+10)")
        
        if result.get('summary_cols_valid'):
            score += 10
            feedback_parts.append("Summary columns valid (+10)")
        else:
            feedback_parts.append("Summary missing required columns")
            
        if result.get('summary_dresses_found'):
            score += 10
            feedback_parts.append("'Dresses' class found in summary (+10)")
        else:
            feedback_parts.append("'Dresses' class missing from summary")
            
        if result.get('summary_score_valid'):
            score += 10
            feedback_parts.append("Sentiment scores in plausible range (+10)")
        else:
            feedback_parts.append("Sentiment scores suspicious (out of range)")
    else:
        feedback_parts.append("Summary CSV not created")

    # 2. Plot (20 points)
    if result.get('plot_exists') and result.get('plot_new'):
        size = result.get('plot_size_kb', 0)
        if size > 10:
            score += 20
            feedback_parts.append(f"Sentiment plot created ({size}KB) (+20)")
        else:
            score += 5
            feedback_parts.append(f"Sentiment plot too small ({size}KB) (+5)")
    else:
        feedback_parts.append("Plot not created")

    # 3. Negative Words CSV (30 points)
    if result.get('neg_exists') and result.get('neg_new'):
        score += 10
        feedback_parts.append("Negative words CSV created (+10)")
        
        if result.get('neg_content_valid'):
            score += 20
            feedback_parts.append("Relevant negative words found (+20)")
        else:
            feedback_parts.append("Content of negative words list seems incorrect")
    else:
        feedback_parts.append("Negative words CSV not created")

    # 4. Code Quality (10 points)
    if result.get('used_tidytext') and result.get('script_modified'):
        score += 10
        feedback_parts.append("Used tidytext package (+10)")
    elif result.get('script_modified'):
        feedback_parts.append("Script modified but tidytext usage not detected")
    else:
        feedback_parts.append("Script not modified")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }