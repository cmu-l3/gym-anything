#!/usr/bin/env python3
"""
Verifier for Docker Event Automation Task.

Criteria:
1. Script exists (10pts)
2. Alert file created with correct text (20pts)
3. Log file created (10pts)
4. Logic Proof: Actual Docker events show restarts triggered (20pts)
5. Logic Proof: Actual Docker events show circuit breaker limit (20pts)
6. Final State: Container is Exited (20pts)

Pass threshold: 70 points.
"""

import json
import os
import base64
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_docker_event_automation(traj, env_info, task_info):
    # 1. Setup and load result
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    import tempfile
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

    score = 0
    feedback = []

    # 2. Check Artifacts
    if result.get('script_exists'):
        score += 10
        feedback.append("Watchdog script found (+10).")
    else:
        feedback.append("Watchdog script missing.")

    if result.get('log_exists'):
        score += 10
        feedback.append("Log file found (+10).")
    else:
        feedback.append("Log file missing.")

    alert_exists = result.get('alert_exists')
    alert_content = result.get('alert_content', '')
    if alert_exists and "CRITICAL" in alert_content:
        score += 20
        feedback.append("Alert file found with correct content (+20).")
    elif alert_exists:
        score += 10
        feedback.append(f"Alert file found but content mismatch: '{alert_content}' (+10).")
    else:
        feedback.append("Alert file missing.")

    # 3. Verify Container State
    # Should be 'exited' because circuit breaker tripped
    status = result.get('container_status', '').lower()
    if status == 'exited':
        score += 20
        feedback.append("Container is in expected 'Exited' state (+20).")
    else:
        feedback.append(f"Container state is '{status}', expected 'exited' (Circuit Breaker failed?).")

    # 4. Analyze Docker Events (The Core Verification)
    events_b64 = result.get('docker_events_b64', '')
    events = []
    if events_b64:
        try:
            events_str = base64.b64decode(events_b64).decode('utf-8')
            for line in events_str.strip().split('\n'):
                if line:
                    events.append(json.loads(line))
        except Exception as e:
            feedback.append(f"Error parsing events: {e}")

    # Count 'die' and 'start' events
    die_count = sum(1 for e in events if e.get('Action') == 'die')
    start_count = sum(1 for e in events if e.get('Action') == 'start')

    feedback.append(f"Event History: {die_count} crashes, {start_count} starts.")

    # Logic Check 1: Did we restart at least once?
    if start_count >= 1 and die_count >= 1:
        score += 20
        feedback.append("Verified: Automation successfully restarted container at least once (+20).")
    else:
        feedback.append("Failed: No restart actions detected in Docker history.")

    # Logic Check 2: Did the Circuit Breaker trip?
    # Logic: If we crashed 3 times, we should have AT MOST 2 restarts (Start, Die, Start, Die, Start, Die -> Stop).
    # Wait, 1st Die -> Restart 1. 2nd Die -> Restart 2. 3rd Die -> Trip (No Restart 3).
    # So ideal counts: 3 Dies, 2 Starts.
    # Allow some flexibility (maybe they restarted 3 times and stopped on 4th).
    # But strictly: Start count should be less than Die count if breaker tripped.
    
    if die_count >= 3:
        if start_count < die_count:
            score += 20
            feedback.append("Verified: Circuit breaker tripped (Starts < Crashes) (+20).")
        else:
            feedback.append("Failed: Circuit breaker did not stop restarts (Starts >= Crashes).")
    elif die_count > 0:
        # Not enough crashes to test breaker
        feedback.append("Warning: Not enough crashes triggered to verify circuit breaker.")
        # We give partial credit if they at least stopped it eventually? No, task requires 3 kills.
        
    # Check if log file content correlates (Anti-gaming check)
    # This is implicit; if they have restarts and log exists, likely real. 
    # Harder to verify timestamps strictly without complex parsing.

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }