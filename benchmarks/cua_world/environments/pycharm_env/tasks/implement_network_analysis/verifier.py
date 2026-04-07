#!/usr/bin/env python3
"""
Verifier for implement_network_analysis task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_implement_network_analysis(traj, env_info, task_info):
    """
    Verify implementation of network analysis algorithms.
    
    Scoring matches task.json metadata:
    - PageRank: 20 pts (3 tests)
    - Betweenness: 20 pts (3 tests)
    - Clustering: 15 pts (2 tests)
    - Community: 15 pts (3 tests)
    - I/O: 20 pts (4 tests)
    - No Regression: 10 pts (4 tests, graph.py)
    
    Penalty:
    - Checksum mismatch (test tampering): Score = 0
    - Remaining stubs: No specific penalty, but tests will likely fail.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/network_analysis_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Anti-gaming check
    if not result.get("integrity", {}).get("checksums_match", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "INTEGRITY CHECK FAILED: Test files or graph.py were modified. You must implement the algorithms without changing the tests."
        }

    breakdown = result.get("breakdown", {})
    score = 0
    feedback_parts = []
    
    # 1. PageRank (20 pts, 3 tests)
    pr_passed = breakdown.get("pagerank_passed", 0)
    if pr_passed == 3:
        score += 20
        feedback_parts.append("PageRank: PASS (20/20)")
    else:
        feedback_parts.append(f"PageRank: FAIL ({pr_passed}/3 tests passed)")

    # 2. Betweenness (20 pts, 3 tests)
    bc_passed = breakdown.get("betweenness_passed", 0)
    if bc_passed == 3:
        score += 20
        feedback_parts.append("Betweenness: PASS (20/20)")
    else:
        feedback_parts.append(f"Betweenness: FAIL ({bc_passed}/3 tests passed)")

    # 3. Clustering (15 pts, 2 tests)
    cc_passed = breakdown.get("clustering_passed", 0)
    if cc_passed == 2:
        score += 15
        feedback_parts.append("Clustering: PASS (15/15)")
    else:
        feedback_parts.append(f"Clustering: FAIL ({cc_passed}/2 tests passed)")

    # 4. Community (15 pts, 3 tests)
    comm_passed = breakdown.get("community_passed", 0)
    if comm_passed == 3:
        score += 15
        feedback_parts.append("Community: PASS (15/15)")
    else:
        feedback_parts.append(f"Community: FAIL ({comm_passed}/3 tests passed)")

    # 5. I/O (20 pts, 4 tests)
    io_passed = breakdown.get("io_passed", 0)
    if io_passed == 4:
        score += 20
        feedback_parts.append("I/O: PASS (20/20)")
    else:
        feedback_parts.append(f"I/O: FAIL ({io_passed}/4 tests passed)")

    # 6. No Regression (10 pts, 4 tests)
    graph_passed = breakdown.get("graph_passed", 0)
    if graph_passed == 4:
        score += 10
        feedback_parts.append("Regression Check: PASS (10/10)")
    else:
        feedback_parts.append(f"Regression Check: FAIL ({graph_passed}/4 tests passed) - graph.py seems broken")

    # Pass threshold
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }