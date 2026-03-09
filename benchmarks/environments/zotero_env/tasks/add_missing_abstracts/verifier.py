#!/usr/bin/env python3
"""
Verifier for add_missing_abstracts task.

Scoring Breakdown (100 pts total):
- Paper 1 (Attention Is All You Need): 28 pts
  - Non-empty: 5 pts
  - Length >= 100 chars: 3 pts
  - Keyphrases (Transformer, attention, encoder/decoder): 20 pts
- Paper 2 (GANs): 28 pts
  - Non-empty: 5 pts
  - Length >= 100 chars: 3 pts
  - Keyphrases (adversarial, generative, discriminative): 20 pts
- Paper 3 (Deep Learning): 28 pts
  - Non-empty: 5 pts
  - Length >= 100 chars: 3 pts
  - Keyphrases (representation, abstraction, backpropagation): 20 pts
- Global Checks: 16 pts
  - Abstracts are distinct (prevent copy-pasting same text): 16 pts

Pass Threshold: 60 pts
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_missing_abstracts(traj, env_info, task_info):
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata keywords
    metadata = task_info.get('metadata', {})
    p1_keys = metadata.get('paper1_keywords', ["Transformer", "attention", "encoder"])
    p2_keys = metadata.get('paper2_keywords', ["adversarial", "generative", "discriminative"])
    p3_keys = metadata.get('paper3_keywords', ["representation", "abstraction", "backpropagation"])
    min_len = metadata.get('min_length', 100)

    # 2. Copy result file
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

    # 3. Evaluate
    score = 0
    feedback_parts = []
    
    abstracts = []

    # Helper function to score a single paper
    def score_paper(paper_data, keywords, paper_name):
        p_score = 0
        p_feedback = []
        
        if not paper_data.get("found", False):
            p_feedback.append(f"{paper_name}: Not found in DB")
            return 0, p_feedback, ""

        abstract = paper_data.get("abstract", "")
        if not abstract:
            p_feedback.append(f"{paper_name}: Abstract empty")
            return 0, p_feedback, ""
        
        # Check 1: Non-empty (5 pts)
        p_score += 5
        
        # Check 2: Length (3 pts)
        if len(abstract) >= min_len:
            p_score += 3
        else:
            p_feedback.append(f"{paper_name}: Abstract too short")

        # Check 3: Keywords (20 pts total, proportional)
        hits = 0
        text_lower = abstract.lower()
        for k in keywords:
            if k.lower() in text_lower:
                hits += 1
        
        if len(keywords) > 0:
            kw_score = int(20 * (hits / len(keywords)))
            p_score += kw_score
            if hits < len(keywords):
                p_feedback.append(f"{paper_name}: Missing some keywords ({hits}/{len(keywords)})")
        
        p_feedback.append(f"{paper_name}: {p_score}/28 pts")
        return p_score, p_feedback, abstract

    # Score Paper 1
    s1, f1, a1 = score_paper(result.get("paper1", {}), p1_keys, "Transformer Paper")
    score += s1
    feedback_parts.extend(f1)
    if a1: abstracts.append(a1)

    # Score Paper 2
    s2, f2, a2 = score_paper(result.get("paper2", {}), p2_keys, "GAN Paper")
    score += s2
    feedback_parts.extend(f2)
    if a2: abstracts.append(a2)

    # Score Paper 3
    s3, f3, a3 = score_paper(result.get("paper3", {}), p3_keys, "Deep Learning Paper")
    score += s3
    feedback_parts.extend(f3)
    if a3: abstracts.append(a3)

    # Global Check: Distinctness (16 pts)
    # If agent pastes the same text into all 3, they fail this
    distinct_score = 0
    if len(abstracts) > 1:
        # Check pairwise equality (simple check)
        # Using set to count unique abstracts
        unique_abs = set(abstracts)
        if len(unique_abs) == len(abstracts):
            distinct_score = 16
            feedback_parts.append("Abstracts are distinct")
        else:
            feedback_parts.append("Duplicate abstracts detected")
    elif len(abstracts) == 1:
        # Only one abstract entered, give partial distinct points? 
        # No, they failed other tasks anyway. Let's give full distinct points 
        # effectively because it is 'distinct' from nothing, but it's minor.
        # Actually, let's just award if distinct count == entered count
        distinct_score = 16
    else:
        # No abstracts entered
        distinct_score = 0

    score += distinct_score

    # Final result
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }