#!/usr/bin/env python3
"""
Verifier for the Java Concurrency Matching Engine task.

Evaluates fixes for 5 concurrency bugs using static analysis (regex) 
combined with dynamic execution results (Exit code 0 and SUCCESS output).
Each fix is worth 20 points. Pass threshold is 80.
"""

import json
import os
import re
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_matching_engine(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Files
    processor_src = result.get("OrderProcessor.java", "")
    engine_src = result.get("MatchingEngine.java", "")
    book_src = result.get("OrderBook.java", "")
    transfer_src = result.get("BalanceTransfer.java", "")
    publisher_src = result.get("MarketPublisher.java", "")
    
    # ── 1. CPU Spin (OrderProcessor.java) ──
    has_take = bool(re.search(r'queue\.take\(\)', processor_src))
    has_poll_timeout = bool(re.search(r'queue\.poll\([^,]+,\s*TimeUnit', processor_src))
    still_has_spin = bool(re.search(r'queue\.poll\(\)\s*;', processor_src))
    
    if (has_take or has_poll_timeout) and not still_has_spin:
        score += 20
        feedback_parts.append("[+] CPU Spin fixed (used blocking take/poll)")
    else:
        feedback_parts.append("[-] CPU Spin bug remains (still using non-blocking poll)")

    # ── 2. Visibility (MatchingEngine.java) ──
    has_volatile = bool(re.search(r'volatile\s+boolean\s+isRunning', engine_src))
    has_atomic = bool(re.search(r'AtomicBoolean\s+isRunning', engine_src))
    
    if has_volatile or has_atomic:
        score += 20
        feedback_parts.append("[+] Visibility fixed (isRunning is volatile/atomic)")
    else:
        feedback_parts.append("[-] Visibility bug remains (isRunning missing volatile)")

    # ── 3. Race Condition (OrderBook.java) ──
    # Valid fixes: method is synchronized OR bestBid is updated inside a sync block
    sync_method = bool(re.search(r'public\s+synchronized\s+void\s+addOrder', book_src))
    sync_block = bool(re.search(r'synchronized\s*\([^)]+\)\s*\{[^}]*bestBid\s*=\s*calculateBestBid\(\)[^}]*\}', book_src, re.DOTALL))
    
    if sync_method or sync_block:
        score += 20
        feedback_parts.append("[+] Race condition fixed (bestBid calculated inside lock)")
    else:
        feedback_parts.append("[-] Race condition remains (bestBid updated outside lock)")

    # ── 4. Deadlock (BalanceTransfer.java) ──
    # Check if lock objects are ordered (id comparison or math.min/max)
    has_ordering_logic = bool(re.search(r'(<|>|compareTo|Math\.min|Math\.max).+synchronized', transfer_src, re.DOTALL))
    
    if has_ordering_logic:
        score += 20
        feedback_parts.append("[+] Deadlock fixed (lock ordering logic implemented)")
    else:
        feedback_parts.append("[-] Deadlock bug remains (inconsistent lock ordering)")

    # ── 5. Concurrent Modification (MarketPublisher.java) ──
    has_cowal = bool(re.search(r'CopyOnWriteArrayList', publisher_src))
    has_sync_list = bool(re.search(r'Collections\.synchronizedList', publisher_src))
    has_sync_block_pub = bool(re.search(r'synchronized\s*\([^)]+\)\s*\{[^}]*for\s*\([^)]+\)\s*\{', publisher_src, re.DOTALL))
    
    if has_cowal or has_sync_list or has_sync_block_pub:
        score += 20
        feedback_parts.append("[+] Thread-safety fixed in publisher")
    else:
        feedback_parts.append("[-] CME bug remains in publisher (missing thread-safe collection/lock)")

    # ── 6. E2E Execution Check ──
    run_log = result.get("run_log", "")
    run_exit_code = result.get("run_exit_code", 1)
    
    if run_exit_code == 0 and "status: SUCCESS" in run_log:
        feedback_parts.append("[+] Load test completed successfully without crashing/hanging")
    elif run_exit_code == 124:
        feedback_parts.append("[-] Load test timed out (Deadlock or CPU Spin triggered)")
    else:
        feedback_parts.append(f"[-] Load test failed (Exit code: {run_exit_code})")

    # Determine pass/fail
    passed = score >= 80 and (run_exit_code == 0)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts),
        "details": {
            "run_exit_code": run_exit_code,
            "log_snippet": run_log[:500]
        }
    }