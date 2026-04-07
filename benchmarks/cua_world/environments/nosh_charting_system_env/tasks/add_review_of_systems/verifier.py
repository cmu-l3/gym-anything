#!/usr/bin/env python3
"""
Verifier for add_review_of_systems task in NOSH ChartingSystem.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_review_of_systems(traj, env_info, task_info):
    """
    Verify that the Review of Systems was correctly added to the encounter.
    
    Scoring:
    - ROS Record Exists (20pts)
    - Anti-gaming: Record created during task (checked via counts)
    - Content Accuracy (80pts split across systems):
        - Constitutional (fatigue/weight)
        - Eyes (vision/pain)
        - ENT (dry mouth)
        - CV (chest pain)
        - Resp (shortness of breath)
        - GI (nausea)
        - GU (frequency/dysuria)
        - Musculoskeletal (joint pain/stiffness)
        - Neuro (headache)
        - Psych (sleep)
        - Skin (rash)
        - Endocrine (heat/cold)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # ============================================================
    # Load Result JSON
    # ============================================================
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Extract data
    ros_found = result.get('ros_found', False)
    ros_record = result.get('ros_record', {})
    initial_count = result.get('initial_count', 0)
    final_count = result.get('final_count', 0)
    
    # ============================================================
    # Check 1: Record Existence and Creation (20 pts)
    # ============================================================
    if ros_found and final_count > initial_count:
        score += 20
        feedback_parts.append("ROS record successfully created.")
    elif ros_found:
        score += 10
        feedback_parts.append("ROS record found, but count suggests it might have existed (check logic).")
    else:
        return {"passed": False, "score": 0, "feedback": "No ROS record found for this encounter."}

    # ============================================================
    # Check 2: Content Verification (80 pts total)
    # 12 systems, approx 6-7 pts each.
    # We will verify key terms from the task description.
    # ============================================================
    
    def check_field(field_key, keywords, field_name, pts):
        content = ros_record.get(field_key, "").lower()
        if not content or content == "null":
            return 0, f"{field_name} empty."
        
        matches = [k for k in keywords if k.lower() in content]
        if len(matches) > 0:
            return pts, f"{field_name} correct."
        else:
            # Partial credit for having non-empty text
            return pts // 2, f"{field_name} has content but missing keywords '{keywords}'."

    # Constitutional: Fatigue, weight loss
    s, f = check_field('ros_gen', ['fatigue', 'weight'], "Constitutional", 10)
    score += s
    feedback_parts.append(f)
    
    # Eyes: vision, pain
    s, f = check_field('ros_eye', ['vision', 'pain', 'neg', 'no'], "Eyes", 5)
    score += s
    
    # ENT: dry mouth
    s, f = check_field('ros_ent', ['dry', 'mouth'], "ENT", 5)
    score += s
    
    # CV: chest pain
    s, f = check_field('ros_cv', ['chest', 'pain', 'neg', 'no'], "CV", 5)
    score += s

    # Respiratory: shortness, breath
    s, f = check_field('ros_resp', ['short', 'breath', 'cough', 'neg', 'no'], "Respiratory", 5)
    score += s
    
    # GI: nausea
    s, f = check_field('ros_gi', ['nausea'], "GI", 8)
    score += s
    feedback_parts.append(f) # Detailed feedback for key positive findings
    
    # GU: frequency, dysuria
    s, f = check_field('ros_gu', ['freq', 'dysuria', 'neg', 'no'], "GU", 5)
    score += s
    
    # Musculoskeletal: joint, pain, stiff
    s, f = check_field('ros_mus', ['joint', 'pain', 'stiff'], "Musculoskeletal", 10)
    score += s
    feedback_parts.append(f)
    
    # Neuro: headache
    s, f = check_field('ros_neuro', ['headache'], "Neuro", 10)
    score += s
    feedback_parts.append(f)
    
    # Psych: sleep
    s, f = check_field('ros_psych', ['sleep', 'insomnia'], "Psych", 7)
    score += s
    
    # Skin: rash
    s, f = check_field('ros_skin', ['rash'], "Skin", 8)
    score += s
    feedback_parts.append(f)
    
    # Endocrine: heat, cold
    s, f = check_field('ros_endocrine', ['heat', 'cold', 'tol', 'neg', 'no'], "Endocrine", 2)
    score += s

    # ============================================================
    # Final Result
    # ============================================================
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }