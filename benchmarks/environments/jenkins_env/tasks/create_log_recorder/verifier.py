#!/usr/bin/env python3
"""
Verifier for create_log_recorder task.
Checks that a custom log recorder was created with the correct loggers and levels.
"""

import json
import os
import sys
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_log_recorder(traj, env_info, task_info):
    """
    Verify the log recorder was created correctly.
    
    Expected configuration:
    - Recorder name: git-debug-recorder
    - Logger: hudson.plugins.git at FINE
    - Logger: org.jenkinsci.plugins.gitclient at FINE
    - Logger: com.cloudbees.plugins.credentials at WARNING
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    target_name = metadata.get('target_recorder_name', 'git-debug-recorder')
    required_loggers = metadata.get('required_loggers', {})
    
    scores = {}
    details = {}
    total_score = 0
    feedback_parts = []
    
    try:
        # Load result file from collected artifacts
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"Failed to load result file: {str(e)}"
            }
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
        
        groovy_data = result.get('groovy_data', {})
        
        # --- Criterion 1: Recorder exists (20 points) ---
        recorder_exists = groovy_data.get("target_found", False)
        if recorder_exists:
            scores["recorder_exists"] = 20
            feedback_parts.append(f"Log recorder '{target_name}' exists")
            total_score += 20
        else:
            scores["recorder_exists"] = 0
            feedback_parts.append(f"Log recorder '{target_name}' NOT found")
            # Early exit if main object missing, but returning structure for consistency
            return {
                "score": 0,
                "passed": False,
                "feedback": "Log recorder not created",
                "details": {"recorder_exists": False}
            }
        
        # Parse target loggers into a lookup dict
        target_loggers = groovy_data.get("target_loggers", [])
        # Normalizing: Logger names from Jenkins are case-sensitive java packages. Levels are uppercase.
        logger_map = {}
        for logger_entry in target_loggers:
            name = logger_entry.get("name", "").strip()
            level = logger_entry.get("level", "").strip().upper()
            if name:
                logger_map[name] = level
        
        details["loggers_found"] = logger_map
        
        # --- Check Loggers (75 points total split among them) ---
        # 3 loggers * 25 points each (15 for presence, 10 for level)
        
        logger_points = 75
        points_per_logger = logger_points / max(1, len(required_loggers))
        
        for req_name, req_level in required_loggers.items():
            req_level = req_level.upper()
            
            # Check Presence
            if req_name in logger_map:
                presence_score = 15
                total_score += presence_score
                feedback_parts.append(f"Logger '{req_name}' found")
                
                # Check Level
                actual_level = logger_map[req_name]
                if actual_level == req_level:
                    level_score = 10
                    total_score += level_score
                    feedback_parts.append(f"Level for '{req_name}' correct ({req_level})")
                else:
                    feedback_parts.append(f"Level for '{req_name}' incorrect (found {actual_level}, expected {req_level})")
            else:
                feedback_parts.append(f"Logger '{req_name}' NOT found")
        
        # --- Criterion 3: HTTP endpoint accessible (5 points) ---
        http_code = result.get("http_endpoint_code", "000")
        if str(http_code) == "200":
            scores["http_endpoint"] = 5
            total_score += 5
        
        # --- Anti-gaming: Check initial state ---
        initial_state = result.get("initial_state", "")
        # Just a sanity check log, explicit scoring usually not needed if "clean state" script worked
        if target_name in initial_state:
            feedback_parts.append("(Note: Recorder existed at start, but setup should have cleared it)")

        passed = total_score >= 70
        
        return {
            "score": int(total_score),
            "passed": passed,
            "feedback": " | ".join(feedback_parts),
            "details": details,
            "scores": scores
        }
    
    except Exception as e:
        import traceback
        return {
            "score": 0,
            "passed": False,
            "feedback": f"Verification error: {str(e)}",
            "details": traceback.format_exc()
        }