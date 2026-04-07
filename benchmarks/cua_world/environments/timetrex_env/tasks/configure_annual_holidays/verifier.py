#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_annual_holidays(traj, env_info, task_info):
    """
    Verify that the four 2026 holidays were correctly created in TimeTrex.
    Uses 'initial_holiday_ids' to ensure the agent didn't just find pre-existing records.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Expected holidays to check against
    metadata = task_info.get('metadata', {})
    expected_holidays = metadata.get('expected_holidays', [
        {"name": "Memorial Day", "date": "2026-05-25"},
        {"name": "Independence Day", "date": "2026-07-03"},
        {"name": "Labor Day", "date": "2026-09-07"},
        {"name": "Thanksgiving Day", "date": "2026-11-26"}
    ])

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_result.close()
        
        copy_from_env("/tmp/configure_annual_holidays_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
            
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found. Export script may have failed."}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid JSON in result file: {e}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    initial_ids = result.get('initial_holiday_ids', [])
    final_holidays = result.get('final_holidays', [])
    
    score = 0
    feedback_parts = []
    
    # Track which IDs have been matched to avoid double-counting
    matched_ids = set()

    for expected in expected_holidays:
        expected_name = expected['name'].strip().lower()
        expected_date = expected['date'].strip()
        
        found_match = False
        
        for h in final_holidays:
            h_id = h.get('id')
            h_name = h.get('name', '').strip().lower()
            h_date = h.get('h_date', '')
            
            if h_id in matched_ids:
                continue
                
            # Check name match (case insensitive) and date match string presence
            if h_name == expected_name and expected_date in str(h_date):
                # Anti-gaming: Verify the record was created during this task sequence
                if h_id not in initial_ids:
                    found_match = True
                    matched_ids.add(h_id)
                    score += 25
                    feedback_parts.append(f"✓ '{expected['name']}' correctly configured for {expected_date}")
                    break
                else:
                    feedback_parts.append(f"✗ '{expected['name']}' existed before task started (Not counted)")
                    break
        
        if not found_match and not any(expected_name in p.lower() for p in feedback_parts):
            feedback_parts.append(f"✗ '{expected['name']}' ({expected_date}) not found or date incorrect")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }