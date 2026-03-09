#!/usr/bin/env python3
"""
Verifier for link_related_papers task.

Verifies that specific bidirectional relations exist between items in the Zotero DB.

Scoring:
- 20 points for each correctly identified pair (5 pairs total).
- Pass threshold: 60 points (3/5 pairs).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_title(t):
    """Normalize title for fuzzy comparison."""
    if not t: return ""
    return "".join(c.lower() for c in t if c.isalnum())

def verify_link_related_papers(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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

    relations_found = result.get("relations_found", [])
    total_relations = result.get("total_relations", 0)
    
    if total_relations == 0:
        return {"passed": False, "score": 0, "feedback": "No 'Related' links found in library."}

    # Define required pairs (normalized for comparison)
    # Use sets of frozensets to handle bidirectionality easily
    # { frozenset({titleA, titleB}), ... }
    
    # Raw required pairs from task description
    required_raw = [
        ("Attention Is All You Need", "BERT: Pre-training of Deep Bidirectional Transformers for Language Understanding"),
        ("Attention Is All You Need", "Language Models are Few-Shot Learners"),
        ("Deep Learning", "ImageNet Classification with Deep Convolutional Neural Networks"),
        ("Deep Learning", "Deep Residual Learning for Image Recognition"),
        ("ImageNet Classification with Deep Convolutional Neural Networks", "Generative Adversarial Nets")
    ]

    # Normalize required pairs for matching
    required_pairs = []
    for a, b in required_raw:
        required_pairs.append({normalize_title(a), normalize_title(b)})

    # Normalize found pairs
    found_pairs = []
    for rel in relations_found:
        s = normalize_title(rel.get("source", ""))
        t = normalize_title(rel.get("target", ""))
        found_pairs.append({s, t})

    score = 0
    feedback_parts = []
    matched_indices = set()

    # Check each required pair
    for i, req_set in enumerate(required_pairs):
        pair_found = False
        
        # Check against all found pairs
        for found_set in found_pairs:
            # We use set intersection/equality
            # Note: Titles might be substrings or exact matches. 
            # Our normalization is aggressive (alnum only), so equality should work 
            # if titles are exact in DB vs Task.
            
            # Allow for substring matching if normalization is tricky
            # Convert sets to lists for substring checks
            req_list = list(req_set)
            found_list = list(found_set)
            
            # Exact set match check
            if req_set == found_set:
                pair_found = True
                break
                
            # Fallback: check if required titles are contained in found titles (robustness)
            if len(req_list) == 2 and len(found_list) == 2:
                # Check both directions
                match_dir1 = (req_list[0] in found_list[0] and req_list[1] in found_list[1])
                match_dir2 = (req_list[0] in found_list[1] and req_list[1] in found_list[0])
                if match_dir1 or match_dir2:
                    pair_found = True
                    break

        if pair_found:
            score += 20
            matched_indices.add(i)
            # Shorten titles for feedback
            t1 = list(required_raw[i])[0][:20] + "..."
            t2 = list(required_raw[i])[1][:20] + "..."
            feedback_parts.append(f"Linked: '{t1}' ↔ '{t2}'")
        else:
            t1 = list(required_raw[i])[0][:20] + "..."
            t2 = list(required_raw[i])[1][:20] + "..."
            feedback_parts.append(f"MISSING: '{t1}' ↔ '{t2}'")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "relations_count": total_relations,
            "matched_pairs": list(matched_indices)
        }
    }