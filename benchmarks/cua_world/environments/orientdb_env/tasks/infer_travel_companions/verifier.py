#!/usr/bin/env python3
"""
Verifier for infer_travel_companions task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_infer_travel_companions(traj, env_info, task_info):
    """
    Verifies that:
    1. The agent seeded the data (2 specific reviews created and linked).
    2. The agent created the PotentialCompanion edge class.
    3. The agent successfully inferred the relationship (edge created between profiles).
    """
    
    # 1. Setup & Read Result
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 2. Verify Seed Data (30 Points)
    # Check John's review
    john_res = result.get("john_review", {}).get("result", [])
    maria_res = result.get("maria_review", {}).get("result", [])
    
    john_seeded = False
    maria_seeded = False
    
    if len(john_res) > 0:
        john_seeded = True
        feedback.append("John's review created and linked correctly.")
    else:
        feedback.append("John's review missing or incorrectly linked (Check Date, Hotel, and Profile).")
        
    if len(maria_res) > 0:
        maria_seeded = True
        feedback.append("Maria's review created and linked correctly.")
    else:
        feedback.append("Maria's review missing or incorrectly linked.")
        
    if john_seeded and maria_seeded:
        score += 30
    elif john_seeded or maria_seeded:
        score += 15

    # 3. Verify Class Creation (10 Points)
    class_res = result.get("class_check", {}).get("result", [])
    class_exists = len(class_res) > 0
    if class_exists:
        score += 10
        feedback.append("Edge class 'PotentialCompanion' exists.")
    else:
        feedback.append("Edge class 'PotentialCompanion' NOT found.")

    # 4. Verify Inference/Edge Creation (50 Points)
    edge_res = result.get("edge_check", {}).get("result", [])
    edge_count = 0
    if edge_res:
        edge_count = edge_res[0].get("cnt", 0)
    
    inference_success = False
    if edge_count >= 1:
        inference_success = True
        score += 50
        feedback.append("Success: 'PotentialCompanion' edge found between John and Maria.")
    else:
        feedback.append("Fail: No 'PotentialCompanion' edge found between the target profiles.")

    # 5. Verify Quality (10 Points)
    # Check for simple execution (no massive duplicates)
    # Ideally edge_count should be 1 or 2 (if bidirectional). If it's 100, something went wrong.
    quality_pass = False
    total_edges = 0
    quality_res = result.get("edge_quality", {}).get("result", [])
    if quality_res:
        total_edges = quality_res[0].get("total_edges", 0)
        
    if inference_success:
        if total_edges <= 10: # Allow some buffer for other coincidences in DB, but demodb is small
            score += 10
            quality_pass = True
            feedback.append("Clean execution: Reasonable number of edges created.")
        else:
            feedback.append(f"Warning: Excessive edges created ({total_edges}). Possible infinite loop or duplicate creation.")
    
    # Final Result
    passed = (score >= 80) and inference_success
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }