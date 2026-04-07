#!/usr/bin/env python3
"""
Verifier for match_recognize_stock_analysis task.

Criteria:
1. CSV Output exists and contains correct pattern data (60 pts)
   - Must identify the correct Start Date (2026-02-03)
   - Must identify the correct Bottom Date (2026-02-05)
   - Must calculate correct Drop % (~11.76%)
2. SQL File exists and uses MATCH_RECOGNIZE (20 pts)
3. Files created during task session (10 pts)
4. CSV formatting (headers present) (10 pts)

Pass threshold: 60 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_match_recognize(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Expected values from metadata
    metadata = task_info.get('metadata', {})
    exp_start = metadata.get('expected_start_date', '2026-02-03')
    exp_bottom = metadata.get('expected_bottom_date', '2026-02-05')
    exp_drop = float(metadata.get('expected_drop_percent', 11.76))

    # Retrieve result JSON
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
        finally:
            try:
                os.unlink(tmp.name)
            except:
                pass

    score = 0
    feedback = []

    # 1. Check SQL Content (20 pts)
    if result.get("sql_exists"):
        if result.get("match_recognize_found"):
            score += 20
            feedback.append("SQL file uses MATCH_RECOGNIZE (+20)")
        else:
            score += 5
            feedback.append("SQL file exists but missing MATCH_RECOGNIZE clause (+5)")
    else:
        feedback.append("SQL file not found (0)")

    # 2. Check CSV Existence & Creation Time (10 pts)
    if result.get("csv_exists"):
        if result.get("files_created_during_task"):
            score += 10
            feedback.append("CSV file created during task (+10)")
        else:
            score += 5
            feedback.append("CSV file exists but timestamp is old (+5)")
    else:
        feedback.append("CSV output file not found (0)")
        return {"passed": False, "score": score, "feedback": "; ".join(feedback)}

    # 3. Check CSV Data Content (70 pts max)
    rows = result.get("rows", [])
    if not rows:
        feedback.append("CSV file is empty or unparsable")
    else:
        # We look for the specific pattern in the rows
        found_pattern = False
        valid_headers = True
        
        # Check headers first (10 pts)
        required_cols = ["START_DATE", "BOTTOM_DATE", "DROP_PERCENT"]
        if rows and all(k in rows[0] for k in required_cols):
             score += 10
             feedback.append("CSV headers correct (+10)")
        else:
             valid_headers = False
             feedback.append(f"Missing required columns in CSV. Found: {list(rows[0].keys()) if rows else 'None'}")

        # Check data values (60 pts)
        if valid_headers:
            for row in rows:
                # Handle potential date format variations (Oracle default often DD-MON-YY)
                # But task description implies ISO or agent format. We check string containment loosely.
                r_start = row.get("START_DATE", "")
                r_bottom = row.get("BOTTOM_DATE", "")
                r_drop = row.get("DROP_PERCENT", "0")

                # Parse drop percent
                try:
                    d_val = float(r_drop)
                except:
                    d_val = 0.0

                # Verify pattern details
                # Date check: '2026-02-03' or '03-FEB-26' matches
                date_match = (exp_start in r_start or "03-FEB-26" in r_start.upper()) and \
                             (exp_bottom in r_bottom or "05-FEB-26" in r_bottom.upper())
                
                # Drop check: 11.76 +/- 0.5
                drop_match = abs(d_val - exp_drop) < 0.5

                if date_match and drop_match:
                    found_pattern = True
                    break
            
            if found_pattern:
                score += 60
                feedback.append("Correct pattern identified in CSV (+60)")
            else:
                feedback.append(f"Pattern data incorrect. Expected Start={exp_start}, Bottom={exp_bottom}, Drop~{exp_drop}%.")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }