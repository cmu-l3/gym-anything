#!/usr/bin/env python3
import json
import os
import tempfile

def verify_fix_raft_consensus(traj, env_info, task_info):
    """
    Verify fixes for Raft Consensus Algorithm.
    
    Scoring:
    1. Fix Split Vote (Randomized Timeout) - 30 pts
       - Verified by test_randomized_timeout
    2. Fix Safety Violation (Term Check) - 30 pts
       - Verified by test_safety_outdated_term
    3. Fix Stale Candidate (Step Down) - 30 pts
       - Verified by test_candidate_steps_down
    4. Cluster Stability - 10 pts
       - Verified by test_leader_election_stabilizes
       
    Pass Threshold: 60 points
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    task_name = "fix_raft_consensus"
    result_path = f"/tmp/{task_name}_result.json"

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
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback = []
    
    # Crit 1: Randomized Timeout (30 pts)
    if result.get("test_randomized_timeout", False):
        score += 30
        feedback.append("Split Vote Fixed: Timeout is randomized (30/30)")
    else:
        feedback.append("Split Vote NOT Fixed: test_randomized_timeout failed")
        
    # Crit 2: Safety Term Check (30 pts)
    if result.get("test_safety_outdated_term", False):
        score += 30
        feedback.append("Safety Fixed: Outdated terms rejected (30/30)")
    else:
        feedback.append("Safety NOT Fixed: test_safety_outdated_term failed")
        
    # Crit 3: Step Down Logic (30 pts)
    if result.get("test_candidate_steps_down", False):
        score += 30
        feedback.append("State Logic Fixed: Candidate steps down on heartbeat (30/30)")
    else:
        feedback.append("State Logic NOT Fixed: test_candidate_steps_down failed")
        
    # Crit 4: Stability (10 pts)
    if result.get("test_leader_election_stabilizes", False):
        score += 10
        feedback.append("Stability Achieved: Cluster elected 1 leader (10/10)")
    else:
        feedback.append("Cluster Unstable: test_leader_election_stabilizes failed")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }