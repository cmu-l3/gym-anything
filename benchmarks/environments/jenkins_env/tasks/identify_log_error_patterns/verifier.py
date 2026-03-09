#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_identify_log_error_patterns(traj, env_info, task_info):
    """
    Verify if the agent correctly identified the builds with SocketTimeoutException.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract data
    output_exists = result.get("output_exists", False)
    file_fresh = result.get("file_created_during_task", False)
    raw_agent_output = result.get("agent_output", "").strip()
    raw_ground_truth = result.get("ground_truth", "").strip()

    feedback_parts = []
    score = 0

    # Criterion 1: File Creation (20 pts)
    if output_exists:
        score += 10
        if file_fresh:
            score += 10
            feedback_parts.append("Output file created during task.")
        else:
            feedback_parts.append("Output file exists but was not modified during task.")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file '/home/ga/timeout_builds.txt' not found."}

    # Normalize and Parse Data
    def parse_builds(s):
        if not s:
            return set()
        # Handle "1, 2, 3" or "1 2 3" or "1,2,3"
        s = s.replace(',', ' ').strip()
        parts = s.split()
        nums = set()
        for p in parts:
            if p.isdigit():
                nums.add(int(p))
        return nums

    agent_set = parse_builds(raw_agent_output)
    truth_set = parse_builds(raw_ground_truth)

    logger.info(f"Agent identified: {agent_set}")
    logger.info(f"Ground truth: {truth_set}")

    # Criterion 2: Correct Identification (60 pts)
    # Full points only for exact match
    if agent_set == truth_set:
        score += 60
        feedback_parts.append(f"Correctly identified all timeout builds: {sorted(list(truth_set))}.")
    else:
        # Partial credit calculations
        missing = truth_set - agent_set
        extra = agent_set - truth_set
        
        if missing:
            feedback_parts.append(f"Missed builds: {sorted(list(missing))}.")
        if extra:
            feedback_parts.append(f"Incorrectly included builds: {sorted(list(extra))}.")
            
        # If they found at least some correct ones
        common = agent_set.intersection(truth_set)
        if common:
            # Partial score: Proportion of correct items found, penalized by false positives
            precision = len(common) / len(agent_set) if agent_set else 0
            recall = len(common) / len(truth_set) if truth_set else 0
            # F1-style weighting? Simpler: 
            # 30 pts for finding at least one correct
            # +30 pts if no false positives
            score += 30 * recall
            if not extra:
                score += 30 * recall # Bonus for high precision
            
            feedback_parts.append(f"Partial match found ({len(common)}/{len(truth_set)}).")

    # Criterion 3: Formatting (20 pts)
    # If we successfully parsed numbers and they were somewhat correct
    if agent_set:
        score += 20
        feedback_parts.append("File format interpreted successfully.")
    else:
        feedback_parts.append("File empty or format unreadable.")

    # Threshold
    passed = (score >= 90) # Requires essentially exact match

    return {
        "passed": passed,
        "score": int(score),
        "feedback": " ".join(feedback_parts)
    }