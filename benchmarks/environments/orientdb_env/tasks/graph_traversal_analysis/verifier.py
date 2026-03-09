#!/usr/bin/env python3
"""
Verifier for Graph Traversal Analysis Task.

Checks:
1. Report file existence and creation time.
2. Parsing of report file for specific keys.
3. Comparison of reported values against live database ground truth.
4. "Do Nothing" check via timestamps.
"""

import json
import base64
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_report_content(content_b64):
    """Decodes and parses the report file content into a dict."""
    if not content_b64:
        return {}
    
    try:
        text = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
        data = {}
        # Look for patterns like KEY: VALUE or KEY = VALUE
        for line in text.splitlines():
            line = line.strip()
            if not line:
                continue
            # Regex to match KEY: VALUE with tolerance for spacing
            match = re.match(r"^([A-Z_]+)\s*[:=]\s*(\d+)", line)
            if match:
                key = match.group(1)
                try:
                    val = int(match.group(2))
                    data[key] = val
                except ValueError:
                    pass
        return data
    except Exception as e:
        logger.error(f"Error parsing report: {e}")
        return {}

def verify_graph_traversal_analysis(traj, env_info, task_info):
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

    # Extract Data
    report_exists = result.get("report_exists", False)
    file_created = result.get("file_created_during_task", False)
    ground_truth = result.get("ground_truth", {})
    agent_data = parse_report_content(result.get("report_content_b64", ""))

    score = 0
    feedback = []

    # 1. File Existence & Anti-Gaming (10 pts)
    if report_exists and file_created:
        score += 10
        feedback.append("Report file created successfully.")
    elif report_exists:
        score += 0 # Failed anti-gaming (file pre-existed or timestamp wrong)
        feedback.append("Report file exists but timestamp invalid (pre-existing?).")
    else:
        return {"passed": False, "score": 0, "feedback": "Report file not found."}

    # 2. Content Verification (90 pts total)
    # Keys to verify
    required_keys = [
        ("TOTAL_VERTICES", 20),
        ("TOTAL_EDGES", 20),
        ("FIVE_STAR_HOTELS", 15),
        ("HOTEL_COUNTRIES", 15),
        ("LUCA_NETWORK_SIZE", 20)
    ]

    all_correct = True

    for key, points in required_keys:
        expected = ground_truth.get(key)
        actual = agent_data.get(key)

        if expected is None:
            feedback.append(f"Internal Error: Missing ground truth for {key}")
            all_correct = False
            continue

        if actual is None:
            feedback.append(f"Missing key in report: {key}")
            all_correct = False
            continue

        # Exact match required for integers
        if actual == expected:
            score += points
            feedback.append(f"{key}: Correct ({actual})")
        else:
            feedback.append(f"{key}: Incorrect (Expected {expected}, Got {actual})")
            all_correct = False

    # 3. Final Assessment
    pass_threshold = 60
    passed = (score >= pass_threshold) and (len(agent_data) >= 3) # At least 3 values parsed

    # Use VLM as a sanity check (optional bonus or penalty, here just logging)
    # We rely primarily on programmatic verification of the data for this data-heavy task.

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }