#!/usr/bin/env python3
"""
Verifier for duplicate_cannibalization_audit task.

Criteria:
1. Duplicate Titles CSV exists, valid structure, created after task start.
2. Duplicate H1s CSV exists, valid structure, created after task start.
3. Content Validation: CSVs must actually contain duplicate data (same value appearing multiple times).
4. Report exists, has meaningful length, and contains quantitative terms.
5. VLM verification of UI interaction.
"""

import json
import tempfile
import os
import csv
import logging
from collections import Counter

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def check_duplicates_in_csv(csv_path, column_keyword):
    """
    Parses a CSV and checks if there are actually duplicate values in the relevant column.
    Returns: (bool: has_duplicates, int: max_duplication_count, int: total_rows)
    """
    if not os.path.exists(csv_path):
        return False, 0, 0
    
    values = []
    col_idx = -1
    
    try:
        with open(csv_path, 'r', encoding='utf-8', errors='replace') as f:
            reader = csv.reader(f)
            headers = next(reader, None)
            if not headers:
                return False, 0, 0
            
            # Find the target column (e.g., "Title 1" or "H1-1")
            for i, h in enumerate(headers):
                if column_keyword.lower() in h.lower() and "length" not in h.lower() and "pixel" not in h.lower():
                    col_idx = i
                    break
            
            if col_idx == -1:
                return False, 0, 0
            
            for row in reader:
                if len(row) > col_idx:
                    val = row[col_idx].strip()
                    if val:
                        values.append(val)
                        
        if not values:
            return False, 0, 0
            
        counts = Counter(values)
        if not counts:
            return False, 0, 0
            
        most_common = counts.most_common(1)
        max_dupe = most_common[0][1] if most_common else 0
        
        # We expect duplicates, so max_dupe should be > 1
        return max_dupe > 1, max_dupe, len(values)
    except Exception as e:
        logger.error(f"Error parsing CSV {csv_path}: {e}")
        return False, 0, 0

def verify_duplicate_cannibalization_audit(traj, env_info, task_info):
    """
    Verify the agent successfully identified and exported duplicate content issues.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    
    # Load basic result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # --- Criterion 1: Titles CSV (30 pts) ---
    titles_info = result.get('titles_file', {})
    if titles_info.get('exists') and titles_info.get('valid_structure'):
        # Verify actual content
        temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        try:
            copy_from_env("/tmp/verify_titles.csv", temp_csv.name)
            has_dupes, max_dupe, rows = check_duplicates_in_csv(temp_csv.name, "Title")
            
            if rows >= 5: # Basic check for content
                score += 15
                if has_dupes:
                    score += 15
                    feedback_parts.append(f"Titles CSV valid ({rows} rows, max dupe count: {max_dupe})")
                else:
                    feedback_parts.append(f"Titles CSV exists but NO duplicates found in 'Title' column")
            else:
                score += 5
                feedback_parts.append(f"Titles CSV exists but very few rows ({rows})")
        except Exception as e:
            feedback_parts.append(f"Titles CSV verification error: {e}")
        finally:
            if os.path.exists(temp_csv.name):
                os.unlink(temp_csv.name)
    else:
        feedback_parts.append("Duplicate Titles CSV missing or invalid")

    # --- Criterion 2: H1s CSV (30 pts) ---
    h1s_info = result.get('h1s_file', {})
    if h1s_info.get('exists') and h1s_info.get('valid_structure'):
        temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        try:
            copy_from_env("/tmp/verify_h1s.csv", temp_csv.name)
            has_dupes, max_dupe, rows = check_duplicates_in_csv(temp_csv.name, "H1")
            
            if rows >= 3:
                score += 15
                if has_dupes:
                    score += 15
                    feedback_parts.append(f"H1 CSV valid ({rows} rows, max dupe count: {max_dupe})")
                else:
                    feedback_parts.append(f"H1 CSV exists but NO duplicates found")
            else:
                score += 5
                feedback_parts.append(f"H1 CSV exists but very few rows ({rows})")
        except Exception as e:
            feedback_parts.append(f"H1 CSV verification error: {e}")
        finally:
            if os.path.exists(temp_csv.name):
                os.unlink(temp_csv.name)
    else:
        feedback_parts.append("Duplicate H1 CSV missing or invalid")

    # --- Criterion 3: Report Analysis (25 pts) ---
    report_info = result.get('report_file', {})
    if report_info.get('exists'):
        if report_info.get('valid_length'):
            # Check keywords in report
            temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
            try:
                copy_from_env("/tmp/verify_report.txt", temp_report.name)
                with open(temp_report.name, 'r', encoding='utf-8', errors='replace') as f:
                    content = f.read().lower()
                    
                keywords = ["duplicate", "count", "recommend", "title", "h1"]
                found_keywords = [k for k in keywords if k in content]
                
                # Check for digits (counts)
                has_numbers = any(c.isdigit() for c in content)
                
                if len(found_keywords) >= 3 and has_numbers:
                    score += 25
                    feedback_parts.append("Report content valid (keywords + numbers found)")
                else:
                    score += 15
                    feedback_parts.append("Report exists but missing key analysis terms/numbers")
            except Exception as e:
                 feedback_parts.append(f"Report verification error: {e}")
            finally:
                if os.path.exists(temp_report.name):
                    os.unlink(temp_report.name)
        else:
            score += 5
            feedback_parts.append("Report exists but is too short (<400 chars)")
    else:
        feedback_parts.append("Report file missing")

    # --- Criterion 4: Screaming Frog Running (15 pts) ---
    if result.get('sf_running'):
        score += 15
        feedback_parts.append("Screaming Frog running")
    else:
        feedback_parts.append("Screaming Frog not running")

    # VLM Check (Bonus/Confirmation) - Optional integration
    # Could add extra 5-10 pts or use as tiebreaker, but strict programmatic is safer here.
    
    # Final Decision
    # Need at least one valid CSV (30) + Report (25) + App (15) = 70 to allow some flexibility,
    # or strictly requiring both CSVs.
    # Pass Threshold: 60 (Allows passing if one CSV is perfect and report is good, or both CSVs good and report weak)
    
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }