#!/usr/bin/env python3
"""
Verifier for demographic_time_tree task.

Criteria:
1. Schema Creation: Classes Year, Month, HasMonth, BornIn must exist.
2. Node Uniqueness:
   - Year nodes must be unique by Value (e.g., only one 1985).
   - Month nodes must be unique per Year (e.g., only one March 1985).
3. Connectivity:
   - Profiles must be connected to Months.
   - Months must be connected to Years.
4. Data Accuracy:
   - The connected Year/Month must match the Profile's Birthday.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_demographic_time_tree(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 1. Schema Verification (20 pts)
    classes = data.get("schema_classes", [])
    required = ["Year", "Month", "HasMonth", "BornIn"]
    missing = [c for c in required if c not in classes]
    
    if not missing:
        score += 20
        feedback.append("Schema classes created successfully.")
    else:
        feedback.append(f"Missing classes: {', '.join(missing)}")
        # If classes are missing, likely nothing else works, but we continue check
    
    # 2. Node Uniqueness (20 pts)
    # Check Year Uniqueness
    year_dist = data.get("year_distribution", [])
    duplicate_years = [y for y in year_dist if y.get('c', 0) > 1]
    
    # Check Month Uniqueness
    # We reconstruct the set of (Year, Month) pairs from the raw data dump
    month_data = data.get("month_data", [])
    seen_pairs = set()
    duplicate_months = 0
    
    for m in month_data:
        m_val = m.get('Value')
        y_vals = m.get('YearVal') # This might be a list if multiple edges, or single value
        
        # Normalize y_vals to a list
        if not isinstance(y_vals, list):
            y_vals = [y_vals] if y_vals is not None else []
            
        for y_val in y_vals:
            pair = (y_val, m_val)
            if pair in seen_pairs:
                duplicate_months += 1
            else:
                seen_pairs.add(pair)

    if len(duplicate_years) == 0 and len(year_dist) > 0:
        score += 10
        feedback.append("Year nodes are unique.")
    elif len(year_dist) == 0:
        feedback.append("No Year nodes found.")
    else:
        feedback.append(f"Found {len(duplicate_years)} duplicated Year values.")

    if duplicate_months == 0 and len(month_data) > 0:
        score += 10
        feedback.append("Month nodes are unique per year.")
    elif len(month_data) == 0:
        feedback.append("No Month nodes found.")
    else:
        feedback.append(f"Found {duplicate_months} duplicate Month nodes (same month/year pair).")

    # 3. Connectivity (30 pts)
    counts = data.get("counts", {})
    profile_count = counts.get("Profiles", 0)
    born_in_count = counts.get("BornIn", 0)
    has_month_count = counts.get("HasMonth", 0)
    month_count = counts.get("Month", 0)

    # Check Profiles -> Month
    # Ideally 1:1, so edge count should approx equal profile count
    if profile_count > 0:
        if born_in_count >= profile_count:
            score += 15
            feedback.append("All profiles appear linked to Months.")
        elif born_in_count > 0:
            prop = born_in_count / profile_count
            score += int(15 * prop)
            feedback.append(f"Partially linked profiles ({born_in_count}/{profile_count}).")
        else:
            feedback.append("No BornIn edges found.")

    # Check Month -> Year
    # Ideally 1:1, so HasMonth count should equal Month count
    if month_count > 0:
        if has_month_count >= month_count:
            score += 15
            feedback.append("All Months appear linked to Years.")
        else:
            feedback.append(f"Some Month nodes are orphans ({has_month_count} edges for {month_count} nodes).")

    # 4. Data Accuracy (30 pts)
    samples = data.get("profile_samples", [])
    valid_samples = 0
    total_samples = 0
    
    for s in samples:
        bday_str = s.get("Birthday")
        m_val = s.get("M")
        y_val = s.get("Y")
        
        # Handle list returns from traverse
        if isinstance(m_val, list): m_val = m_val[0] if m_val else None
        if isinstance(y_val, list): y_val = y_val[0] if y_val else None
        
        if bday_str and m_val is not None and y_val is not None:
            total_samples += 1
            # Parse date "YYYY-MM-DD..."
            try:
                # OrientDB often returns ISO format
                dt = datetime.strptime(bday_str.split('T')[0], "%Y-%m-%d")
                if dt.year == y_val and dt.month == m_val:
                    valid_samples += 1
            except ValueError:
                pass # Date parse error

    if total_samples > 0:
        accuracy = valid_samples / total_samples
        pts = int(30 * accuracy)
        score += pts
        if accuracy > 0.9:
            feedback.append("Data accuracy looks good (Years/Months match Birthdays).")
        else:
            feedback.append(f"Data accuracy issues: {valid_samples}/{total_samples} samples correct.")
    else:
        feedback.append("Could not verify data accuracy (no valid samples).")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " ".join(feedback)
    }