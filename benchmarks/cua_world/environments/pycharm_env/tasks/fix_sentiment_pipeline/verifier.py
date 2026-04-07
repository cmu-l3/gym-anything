#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_sentiment_pipeline(traj, env_info, task_info):
    """
    Verify the fix_sentiment_pipeline task.
    
    Scoring Criteria:
    1. Negation Handling (30 pts): test_negation_preservation passes
    2. Tokenization Fix (30 pts): test_short_words_included passes
    3. Logic Correction (20 pts): test_prediction_logic passes
    4. Model Accuracy (20 pts): F1 Score > 0.85 on hidden test set
    
    Pass Threshold: 80 points
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}
        
    result_path = "/tmp/fix_sentiment_pipeline_result.json"
    
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".json") as tmp:
            tmp_path = tmp.name
        try:
            copy_from_env(result_path, tmp_path)
            with open(tmp_path, "r") as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
        
    score = 0
    feedback = []
    
    # Criterion 1: Negation Handling (30 pts)
    if result.get("negation_test_pass", False):
        score += 30
        feedback.append("Negation handling fixed (test passed)")
    else:
        feedback.append("Negation handling NOT fixed (test failed)")
        
    # Criterion 2: Short Words/Tokenization (30 pts)
    if result.get("short_words_test_pass", False):
        score += 30
        feedback.append("Tokenization/Short words fixed (test passed)")
    else:
        feedback.append("Tokenization NOT fixed (short words still ignored)")
        
    # Criterion 3: Logic Correction (20 pts)
    if result.get("logic_test_pass", False):
        score += 20
        feedback.append("Prediction logic fixed (test passed)")
    else:
        feedback.append("Prediction logic NOT fixed (test failed)")
        
    # Criterion 4: Hidden Accuracy (20 pts)
    f1 = float(result.get("hidden_f1", 0.0))
    accuracy = float(result.get("hidden_accuracy", 0.0))
    threshold = 0.85
    
    if f1 >= threshold:
        score += 20
        feedback.append(f"Model accuracy good (F1: {f1:.2f})")
    elif f1 > 0.5:
        # Partial credit if they improved it but not enough? 
        # No, the logic bug makes it terrible, fixing all 3 guarantees high score
        score += 5
        feedback.append(f"Model accuracy improved but low (F1: {f1:.2f})")
    else:
        feedback.append(f"Model accuracy poor (F1: {f1:.2f})")
        
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }