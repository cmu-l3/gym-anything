#!/usr/bin/env python3
import json
import os
import tempfile

def verify_fix_ical_parser(traj, env_info, task_info):
    """
    Verifies the fix_ical_parser task.
    
    Scoring Criteria:
    - Public Test Suite Pass: 40 pts
    - Hidden Stress Test:
      - Line Unfolding: 20 pts
      - Parameter Handling: 20 pts
      - Date/Time Logic: 20 pts
      
    Anti-gaming:
    - File must be modified during the task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Read result from container
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
            
    score = 0
    feedback = []
    
    # 1. Anti-gaming Check
    if not result.get('file_modified', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "FAILED: parser.py was not modified during the task."
        }

    # 2. Public Tests (40 pts)
    # 4 tests in public suite. 10 pts each roughly.
    public_passed = result.get('public_tests_passed', 0)
    # We expect 4 public tests
    score += (public_passed * 10) 
    if public_passed == 4:
        feedback.append("Public Test Suite: PASS (40/40)")
    else:
        feedback.append(f"Public Test Suite: {public_passed}/4 passed")

    # 3. Hidden Tests (60 pts)
    # Output format: "UNFOLD_SUMMARY_PASS|UNFOLD_DESC_PASS|DTSTART_PASS|DTEND_PASS"
    hidden_out = result.get('hidden_output', '')
    
    if "CRASH" in hidden_out or "IMPORT_ERROR" in hidden_out:
        feedback.append(f"Hidden Verification: CRASHED ({hidden_out})")
    else:
        # Check Unfolding (20 pts)
        if "UNFOLD_SUMMARY_PASS" in hidden_out and "UNFOLD_DESC_PASS" in hidden_out:
            score += 20
            feedback.append("Hidden: Line Unfolding Logic Verified (+20)")
        elif "UNFOLD" in hidden_out:
            score += 10
            feedback.append("Hidden: Partial Unfolding Logic (+10)")
        else:
            feedback.append("Hidden: Line Unfolding FAILED")
            
        # Check Parameter Handling (DTSTART with TZID) (20 pts)
        if "DTSTART_PASS" in hidden_out:
            score += 20
            feedback.append("Hidden: Parameter Parsing Verified (+20)")
        else:
            feedback.append("Hidden: Parameter Parsing FAILED")
            
        # Check Date Logic (Date-only parsing) (20 pts)
        if "DTEND_PASS" in hidden_out:
            score += 20
            feedback.append("Hidden: Date-only Parsing Verified (+20)")
        else:
            feedback.append("Hidden: Date-only Parsing FAILED")

    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }