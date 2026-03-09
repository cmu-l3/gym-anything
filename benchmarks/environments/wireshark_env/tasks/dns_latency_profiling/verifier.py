#!/usr/bin/env python3
"""
Verifier for DNS Latency Profiling task.
Compares agent's generated report against ground truth pre-calculated in setup.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_dns_latency_profiling(traj, env_info, task_info):
    """
    Verify the DNS latency report.
    
    Scoring:
    - Report file exists & created during task: 5 pts
    - Format compliance (headers): 10 pts
    - Count accuracy (Total, Answered, Unanswered): 35 pts
    - Latency stats accuracy (Min, Max, Mean, Median): 40 pts
    - Slowest domain accuracy: 10 pts
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 2. Check File Existence and Creation
    if not result.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Report file not found."}
        
    if not result.get('file_created_during_task'):
        feedback.append("Warning: File timestamp indicates it wasn't modified during task.")
    else:
        score += 5
        feedback.append("Report file created successfully.")

    content = result.get('output_content', '')
    gt = result.get('ground_truth', {})
    gt_stats = gt.get('stats', {})

    # 3. Check Format (Headers)
    required_headers = [
        "DNS Latency Profiling Report",
        "Latency Statistics (ms):",
        "Slowest Resolution:"
    ]
    missing_headers = [h for h in required_headers if h not in content]
    
    if not missing_headers:
        score += 10
        feedback.append("Report format looks correct.")
    else:
        feedback.append(f"Missing headers: {', '.join(missing_headers)}")

    # 4. Helper to extract values
    def extract_value(pattern, text, default=None):
        match = re.search(pattern, text, re.IGNORECASE)
        return match.group(1).strip() if match else default

    # 5. Verify Counts (35 pts total)
    # Tolerances: Exact match preferred, but typically exact for counts
    
    # Extract
    try:
        user_total = int(extract_value(r"Total DNS Queries:\s*(\d+)", content, -1))
        user_answered = int(extract_value(r"Queries With Response:\s*(\d+)", content, -1))
        user_unanswered = int(extract_value(r"Unanswered Queries:\s*(\d+)", content, -1))
    except ValueError:
        user_total, user_answered, user_unanswered = -1, -1, -1

    # Compare Total (15 pts)
    if user_total == gt.get('total_queries'):
        score += 15
        feedback.append(f"Total queries correct ({user_total}).")
    else:
        feedback.append(f"Total queries mismatch (Expected: {gt.get('total_queries')}, Got: {user_total}).")

    # Compare Answered (10 pts)
    if user_answered == gt.get('answered_queries'):
        score += 10
        feedback.append(f"Answered queries correct ({user_answered}).")
    else:
        feedback.append(f"Answered queries mismatch (Expected: {gt.get('answered_queries')}, Got: {user_answered}).")

    # Compare Unanswered (10 pts)
    if user_unanswered == gt.get('unanswered_queries'):
        score += 10
        feedback.append(f"Unanswered queries correct ({user_unanswered}).")
    else:
        feedback.append(f"Unanswered queries mismatch (Expected: {gt.get('unanswered_queries')}, Got: {user_unanswered}).")

    # 6. Verify Statistics (40 pts total)
    # Tolerance: 0.5 ms (rounding differences between Python and Wireshark/Agent)
    
    def check_stat(name, pattern, expected, points, tolerance=0.5):
        val_str = extract_value(pattern, content)
        if val_str:
            try:
                # Remove 'ms' if present
                val = float(val_str.replace('ms', '').strip())
                if abs(val - expected) <= tolerance:
                    return points, f"{name} correct ({val})."
                else:
                    return 0, f"{name} mismatch (Expected: {expected:.3f}, Got: {val})."
            except ValueError:
                return 0, f"{name} invalid format."
        return 0, f"{name} not found."

    s_min, f_min = check_stat("Min Latency", r"Minimum:\s*([\d\.]+)", gt_stats.get('min', 0), 10)
    score += s_min; feedback.append(f_min)

    s_max, f_max = check_stat("Max Latency", r"Maximum:\s*([\d\.]+)", gt_stats.get('max', 0), 10)
    score += s_max; feedback.append(f_max)

    s_mean, f_mean = check_stat("Mean Latency", r"Mean:\s*([\d\.]+)", gt_stats.get('mean', 0), 10)
    score += s_mean; feedback.append(f_mean)

    s_med, f_med = check_stat("Median Latency", r"Median:\s*([\d\.]+)", gt_stats.get('median', 0), 10)
    score += s_med; feedback.append(f_med)

    # 7. Verify Slowest Domain (10 pts)
    user_domain = extract_value(r"Domain:\s*([^\n]+)", content, "")
    expected_domain = gt_stats.get('slowest_domain', '')
    
    # Case insensitive check, strip trailing dots if any
    if user_domain and expected_domain and user_domain.lower().strip('.') == expected_domain.lower().strip('.'):
        score += 10
        feedback.append(f"Slowest domain correct ({user_domain}).")
    else:
        feedback.append(f"Slowest domain mismatch (Expected: {expected_domain}, Got: {user_domain}).")

    # 8. Final Result
    passed = score >= 60  # Require good effort to pass
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }