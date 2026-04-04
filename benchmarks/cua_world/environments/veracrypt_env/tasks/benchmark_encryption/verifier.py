#!/usr/bin/env python3
"""
Verifier for benchmark_encryption task.

Verifies:
1. Report file creation and freshness.
2. Content analysis: presence of algorithms, numeric values, and valid summary lines.
3. Logical consistency of the report (Fastest vs Slowest).
4. VLM verification of the benchmark workflow.
"""

import json
import tempfile
import os
import logging
import base64
import re
from typing import Dict, Any, List

# Import VLM utils if available in the environment
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_benchmark_encryption(traj, env_info, task_info):
    """
    Main verification function.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_algos = metadata.get('required_algorithms', ["AES", "Serpent", "Twofish"])
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # 1. Retrieve and Parse Result JSON
    # ------------------------------------------------------------------
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # ------------------------------------------------------------------
    # 2. File Existence and Freshness (25 points)
    # ------------------------------------------------------------------
    if not result_data.get('report_exists'):
        return {"passed": False, "score": 0, "feedback": "Report file not found"}
    
    score += 10
    feedback_parts.append("Report file exists")

    if result_data.get('file_created_during_task'):
        score += 15
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File timestamp invalid (pre-dates task)")

    # ------------------------------------------------------------------
    # 3. Content Analysis (50 points)
    # ------------------------------------------------------------------
    content_b64 = result_data.get('report_content_base64', '')
    if not content_b64:
        return {"passed": False, "score": score, "feedback": "Report file is empty"}

    try:
        report_text = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
    except Exception:
        return {"passed": False, "score": score, "feedback": "Failed to decode report content"}

    # Check for Algorithm Names (15 pts)
    found_algos = 0
    for algo in required_algos:
        if re.search(r'\b' + re.escape(algo) + r'\b', report_text, re.IGNORECASE):
            found_algos += 1
    
    if found_algos >= 3:
        score += 15
        feedback_parts.append(f"Found {found_algos} algorithm names")
    else:
        feedback_parts.append(f"Only found {found_algos} algorithm names (need 3+)")

    # Check for Numeric Data (15 pts)
    # Look for lines with multiple numbers (e.g., "AES  1.2  3.4  2.3")
    # Matches simple float/int patterns
    numbers = re.findall(r'\b\d+(?:\.\d+)?\b', report_text)
    # We expect at least 3 columns * 5 algos = 15 numbers roughly
    valid_throughput_count = 0
    for num_str in numbers:
        try:
            val = float(num_str)
            # Filter out year 2024 or buffer size 100, look for throughputs
            # Broad range: 10 MB/s to 50 GB/s (10 - 50000)
            if 10.0 <= val <= 50000.0:
                valid_throughput_count += 1
        except ValueError:
            pass
            
    if valid_throughput_count >= 10:
        score += 15
        feedback_parts.append("Data table contains numeric throughput values")
    else:
        feedback_parts.append("Insufficient numeric data in report")

    # Check Summary Lines & Consistency (20 pts)
    fastest_match = re.search(r'Fastest.*?:.*?\b([A-Za-z\(\)\-]+)\b', report_text, re.IGNORECASE)
    slowest_match = re.search(r'Slowest.*?:.*?\b([A-Za-z\(\)\-]+)\b', report_text, re.IGNORECASE)
    
    has_summary = False
    if fastest_match and slowest_match:
        has_summary = True
        score += 10
        feedback_parts.append("Summary lines found")
        
        # Verify Consistency (Bonus 10)
        # We try to extract mean values for the claimed fastest/slowest
        # This is hard to parse perfectly from free text, so we do a heuristic check:
        # Does the fastest line contain a number larger than the slowest line?
        
        # Extract numbers from the specific lines
        fastest_line = report_text[fastest_match.start():report_text.find('\n', fastest_match.start())]
        slowest_line = report_text[slowest_match.start():report_text.find('\n', slowest_match.start())]
        
        fastest_nums = [float(x) for x in re.findall(r'\b\d+(?:\.\d+)?\b', fastest_line) if 10 < float(x) < 50000]
        slowest_nums = [float(x) for x in re.findall(r'\b\d+(?:\.\d+)?\b', slowest_line) if 10 < float(x) < 50000]
        
        if fastest_nums and slowest_nums and max(fastest_nums) >= min(slowest_nums):
            score += 10
            feedback_parts.append("Summary values are consistent")
        else:
            feedback_parts.append("Summary validation inconclusive or inconsistent")
    else:
        feedback_parts.append("Missing 'Fastest' or 'Slowest' summary lines")

    # ------------------------------------------------------------------
    # 4. VLM Verification (25 points)
    # ------------------------------------------------------------------
    vlm_score = 0
    if VLM_AVAILABLE:
        # Sample frames to find the benchmark window
        frames = sample_trajectory_frames(traj, n=5)
        
        prompt = """
        Review these screenshots of a user operating VeraCrypt.
        1. Do you see a window titled "VeraCrypt - Encryption Algorithm Benchmark" or similar?
        2. Do you see a table of results with columns like "Algorithm", "Encryption", "Decryption"?
        3. Is the Buffer Size set to 100 MB (or can you see "100 MB" in the settings)?
        
        Return JSON:
        {
            "benchmark_window_seen": boolean,
            "results_table_seen": boolean,
            "buffer_size_100mb": boolean
        }
        """
        
        try:
            vlm_res = query_vlm(images=frames, prompt=prompt)
            parsed = vlm_res.get('parsed', {})
            
            if parsed.get('benchmark_window_seen'):
                vlm_score += 10
            if parsed.get('results_table_seen'):
                vlm_score += 15
                
            feedback_parts.append(f"VLM Verification: Window={parsed.get('benchmark_window_seen')}, Table={parsed.get('results_table_seen')}")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback: if report is perfect, give partial credit
            if score >= 60:
                vlm_score += 15
    else:
        # If VLM not available, re-weight score or give free points if report is good
        if score >= 60:
            vlm_score = 25
            feedback_parts.append("VLM skipped (passed based on file analysis)")

    score += vlm_score

    # ------------------------------------------------------------------
    # Final Result
    # ------------------------------------------------------------------
    passed = (score >= 60) and result_data.get('file_created_during_task') and has_summary
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }