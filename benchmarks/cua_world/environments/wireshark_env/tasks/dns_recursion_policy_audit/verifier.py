#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_dns_audit(traj, env_info, task_info):
    """
    Verifies the DNS Recursion Policy Audit task.
    
    Scoring Breakdown (100 pts total):
    1. PCAP Output (50 pts):
       - Exists and created during task: 10 pts
       - Completeness (packet count matches ground truth): 15 pts
       - Accuracy (contains ONLY RD=1 packets): 25 pts
    
    2. JSON Report (50 pts):
       - Exists and valid JSON: 10 pts
       - recursive_queries_count accuracy: 10 pts
       - recursion_available_count accuracy: 10 pts
       - server_supports_recursion conclusion: 20 pts
    """
    
    # 1. Retrieve Result Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Parse Data
    pcap_info = result_data.get('pcap_verification', {})
    report_info = result_data.get('report_verification', {})
    ground_truth = result_data.get('ground_truth', {})
    
    score = 0
    feedback = []
    
    # --- Verify PCAP (50 pts) ---
    gt_rd_count = ground_truth.get('recursive_queries_count', -1)
    
    # Criterion 1: Existence & Timestamp (10 pts)
    if pcap_info.get('exists') and pcap_info.get('created_during_task'):
        score += 10
        feedback.append("PCAP file created successfully.")
        
        # Criterion 2: Completeness (15 pts)
        user_pcap_count = pcap_info.get('total_packets', 0)
        if user_pcap_count == gt_rd_count:
            score += 15
            feedback.append(f"PCAP contains correct number of packets ({user_pcap_count}).")
        else:
            feedback.append(f"PCAP packet count mismatch: Found {user_pcap_count}, Expected {gt_rd_count}.")
            
        # Criterion 3: Accuracy (25 pts)
        bad_packets = pcap_info.get('bad_packets_count', 0)
        if bad_packets == 0 and user_pcap_count > 0:
            score += 25
            feedback.append("PCAP correctly filtered (no non-recursive queries found).")
        elif user_pcap_count > 0:
            feedback.append(f"PCAP verification failed: Found {bad_packets} packets without RD flag set.")
    else:
        feedback.append("PCAP file not found or not created during task.")

    # --- Verify Report (50 pts) ---
    
    # Criterion 4: Existence & Format (10 pts)
    report_content = report_info.get('content', {})
    if report_info.get('exists') and isinstance(report_content, dict) and report_content:
        score += 10
        feedback.append("JSON report found and parsed.")
        
        # Criterion 5: Recursive Queries Count (10 pts)
        user_rd = report_content.get('recursive_queries_count')
        if user_rd == gt_rd_count:
            score += 10
            feedback.append("Report: 'recursive_queries_count' is correct.")
        else:
            feedback.append(f"Report: 'recursive_queries_count' incorrect. Got {user_rd}, Expected {gt_rd_count}.")
            
        # Criterion 6: Recursion Available Count (10 pts)
        gt_ra_count = ground_truth.get('recursion_available_count', -1)
        user_ra = report_content.get('recursion_available_count')
        if user_ra == gt_ra_count:
            score += 10
            feedback.append("Report: 'recursion_available_count' is correct.")
        else:
            feedback.append(f"Report: 'recursion_available_count' incorrect. Got {user_ra}, Expected {gt_ra_count}.")
            
        # Criterion 7: Conclusion (20 pts)
        gt_supports = ground_truth.get('server_supports_recursion')
        user_supports = report_content.get('server_supports_recursion')
        
        # Handle string/bool type mismatches loosely
        if str(user_supports).lower() == str(gt_supports).lower():
            score += 20
            feedback.append("Report: Conclusion on recursion support is correct.")
        else:
            feedback.append(f"Report: Conclusion incorrect. Got {user_supports}, Expected {gt_supports}.")
            
    else:
        feedback.append("JSON report missing or invalid format.")

    # Final Result
    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }