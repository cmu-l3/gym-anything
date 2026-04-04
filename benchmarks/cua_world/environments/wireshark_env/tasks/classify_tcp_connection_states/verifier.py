#!/usr/bin/env python3
"""
Verifier for classify_tcp_connection_states task.

Checks if the agent correctly analyzed the PCAP and produced the required metrics.
Metrics verified:
1. Total TCP streams
2. SYN packets (initiation attempts)
3. Streams with RST
4. Streams with FIN
5. Unanswered SYN streams
6. Largest stream index
7. Largest stream packet count
"""

import json
import tempfile
import os
import re

def parse_report_content(content):
    """
    Parses key-value pairs from the report content.
    Expects format: 'key: value'
    Returns a dictionary of normalized keys to integer values.
    """
    data = {}
    if not content:
        return data
        
    for line in content.splitlines():
        if ':' in line:
            key, val = line.split(':', 1)
            key = key.strip().lower()
            val = val.strip()
            # extract first number found in value
            nums = re.findall(r'\d+', val)
            if nums:
                try:
                    data[key] = int(nums[0])
                except ValueError:
                    pass
    return data

def verify_classify_tcp_connection_states(traj, env_info, task_info):
    """
    Verifies the TCP classification task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file from container
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

    # Initialize scoring
    score = 0
    max_score = 100
    feedback_parts = []
    
    # Check 1: File Existence & Anti-Gaming (15 pts)
    if not result.get('report_exists'):
        return {"passed": False, "score": 0, "feedback": "Report file not found at expected location."}
    
    score += 5
    if result.get('report_created_during_task'):
        score += 10
        feedback_parts.append("Report created during task.")
    else:
        feedback_parts.append("Report file exists but timestamp predates task (stale file?).")

    # Parse Agent Data
    agent_data = parse_report_content(result.get('report_content', ''))
    ground_truth = result.get('ground_truth', {})
    
    required_keys = [
        'total_tcp_streams', 
        'syn_packets', 
        'streams_with_rst', 
        'streams_with_fin', 
        'unanswered_syn_streams', 
        'largest_stream_index', 
        'largest_stream_packet_count'
    ]
    
    # Check 2: Metric Accuracy (85 pts total)
    # Weights vary slightly based on difficulty
    
    # Helper to score a metric
    def score_metric(key, points, tolerance=0):
        agent_val = agent_data.get(key)
        gt_val = ground_truth.get(key)
        
        if agent_val is None:
            feedback_parts.append(f"Missing {key}.")
            return 0
        
        if gt_val is None:
             # Should not happen if setup ran correctly
            feedback_parts.append(f"System error: missing ground truth for {key}.")
            return 0
            
        diff = abs(agent_val - gt_val)
        if diff <= tolerance:
            feedback_parts.append(f"{key}: Correct ({agent_val}).")
            return points
        else:
            feedback_parts.append(f"{key}: Incorrect (Got {agent_val}, Expected {gt_val}).")
            return 0

    # 1. Total TCP streams (10 pts)
    score += score_metric('total_tcp_streams', 10, tolerance=0)
    
    # 2. SYN packets (10 pts)
    score += score_metric('syn_packets', 10, tolerance=0)
    
    # 3. RST streams (15 pts) - slightly harder filter
    score += score_metric('streams_with_rst', 15, tolerance=0)
    
    # 4. FIN streams (10 pts)
    score += score_metric('streams_with_fin', 10, tolerance=0)
    
    # 5. Unanswered SYN (20 pts) - hardest logic
    score += score_metric('unanswered_syn_streams', 20, tolerance=1) # Allow off-by-one for edge cases
    
    # 6. Largest stream index (10 pts)
    score += score_metric('largest_stream_index', 10, tolerance=0)
    
    # 7. Largest stream packet count (10 pts)
    score += score_metric('largest_stream_packet_count', 10, tolerance=0)

    # Final Pass/Fail logic
    # Pass if score >= 60 AND file was created during task
    passed = (score >= 60) and result.get('report_created_during_task')

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }