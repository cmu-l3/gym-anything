#!/usr/bin/env python3
"""
Verifier for network_incident_har_capture task.

Verifies:
1. HAR file existence and validity (JSON format).
2. "Preserve log" usage (evidence of multiple page loads in one file).
3. Specific network events captured:
   - POST request to /forms/post
   - High latency request (>2s) to /delay/3
   - 503 error from /status/503
"""

import json
import os
import tempfile
import logging
from urllib.parse import urlparse

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_network_incident_har_capture(traj, env_info, task_info):
    """
    Verify the HAR file captures the required network incident sequence.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve result metadata
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Basic checks
    if not result.get('har_exists', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No HAR file found at /home/ga/Desktop/incident_trace.har"
        }
    
    if not result.get('file_created_during_task', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "File timestamp is older than task start time (anti-gaming check failed)"
        }

    # 2. Retrieve and Parse HAR file
    temp_har = tempfile.NamedTemporaryFile(delete=False, suffix='.har')
    try:
        copy_from_env("/tmp/exported_trace.har", temp_har.name)
        with open(temp_har.name, 'r', encoding='utf-8', errors='replace') as f:
            har_data = json.load(f)
    except json.JSONDecodeError:
        return {"passed": False, "score": 10, "feedback": "File exists but is not valid JSON/HAR format"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read HAR file: {e}"}
    finally:
        if os.path.exists(temp_har.name):
            os.unlink(temp_har.name)

    # 3. Analyze HAR Content
    score = 10  # Base score for valid file
    feedback = ["File is valid HAR/JSON"]
    
    entries = har_data.get('log', {}).get('entries', [])
    if not entries:
        return {"passed": False, "score": 10, "feedback": "HAR file contains no entries"}

    # Flags for specific events
    found_post = False
    found_delay = False
    found_error = False
    
    # Iterate through entries to find evidence
    for entry in entries:
        req = entry.get('request', {})
        res = entry.get('response', {})
        url = req.get('url', '')
        
        # Check for Form POST
        if 'httpbin.org/forms/post' in url and req.get('method') == 'POST':
            found_post = True
            
        # Check for Delay (Latent request)
        # httpbin delay isn't exact, but should be > 2000ms for /delay/3
        if 'httpbin.org/delay/3' in url:
            time_ms = entry.get('time', 0)
            # Accept anything over 2000ms as evidence of the 3s delay
            if time_ms > 2000:
                found_delay = True
                
        # Check for 503 Error
        if 'httpbin.org/status/503' in url:
            if res.get('status') == 503:
                found_error = True

    # Scoring Logic
    if found_post:
        score += 20
        feedback.append("POST request captured")
    else:
        feedback.append("Missing POST request to /forms/post")

    if found_delay:
        score += 20
        feedback.append("Latency event captured (>2s)")
    else:
        feedback.append("Missing or too fast response for /delay/3")

    if found_error:
        score += 20
        feedback.append("503 Error captured")
    else:
        feedback.append("Missing 503 status code for /status/503")

    # Check for "Preserve log" (Multiple distinct navigation events in one file)
    # If the user didn't preserve log, navigating to the next page would clear the previous entries.
    # Therefore, finding ALL THREE specific URL patterns in one file proves Preserve Log was on.
    if found_post and found_delay and found_error:
        score += 30
        feedback.append("Preserve Log verified (all events present in single trace)")
    else:
        feedback.append("Trace incomplete (Preserve Log likely disabled or steps skipped)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }