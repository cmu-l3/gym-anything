#!/usr/bin/env python3
import json
import tempfile
import os
import re
from datetime import datetime

def parse_date(date_str):
    """
    Robustly parse date strings entered into Zotero.
    Returns (year, month, day) or (None, None, None) on failure.
    
    Supported formats examples:
    - 1953-04-25
    - April 25, 1953
    - 25 April 1953
    - 25 Apr 1953
    - 04/25/1953 (US)
    """
    if not date_str:
        return None, None, None
        
    date_str = date_str.strip()
    
    # Map text months to numbers
    months = {
        'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
        'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
        'january': 1, 'february': 2, 'march': 3, 'april': 4, 'may': 5, 'june': 6,
        'july': 7, 'august': 8, 'september': 9, 'october': 10, 'november': 11, 'december': 12
    }

    try:
        # Regex for YYYY-MM-DD
        m_iso = re.match(r'^(\d{4})-(\d{1,2})-(\d{1,2})$', date_str)
        if m_iso:
            return int(m_iso.group(1)), int(m_iso.group(2)), int(m_iso.group(3))

        # Regex for text based months (e.g., April 25, 1953 or 25 Apr 1953)
        # Finds a year (19xx or 20xx) and looks for month names
        parts = re.split(r'[\s,\-/]+', date_str.lower())
        
        year = None
        month = None
        day = None
        
        for part in parts:
            if part.isdigit():
                val = int(part)
                if val > 1900:
                    year = val
                elif 1 <= val <= 31:
                    # Ambiguity between month and day handled loosely: 
                    # If we already have a day, this might be month? 
                    # Simpler strategy: assume day is the smaller number if we find a month name elsewhere
                    # If strictly numeric (04/25/1953), we assume US format (M/D/Y) usually, 
                    # but let's stick to identifying the specific components
                    if day is None:
                        day = val
                    elif month is None and val <= 12:
                        month = val
            elif part in months:
                month = months[part]
        
        # Numeric fallback for formats like 2015/05/28
        if year and not month and not day:
            # Re-try strict numeric parse
            nums = re.findall(r'\d+', date_str)
            if len(nums) == 3:
                # Heuristic: Year is usually first or last. 
                # If first is > 1900 -> YMD
                # If last is > 1900 -> MDY or DMY
                n1, n2, n3 = map(int, nums)
                if n1 > 1900: year, month, day = n1, n2, n3
                elif n3 > 1900: year, month, day = n3, n1, n2 # Assume MDY default for en-US
        
        return year, month, day

    except Exception:
        return None, None, None

def verify_add_precise_publication_dates(traj, env_info, task_info):
    """
    Verifies that the agent correctly updated the publication dates for 4 papers.
    Scores 25 points per paper (15 for correct year/month, +10 for correct day).
    Checks anti-gaming timestamps.
    """
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function unavailable"}

    # Load targets from metadata
    targets = task_info.get('metadata', {}).get('targets', [])
    if not targets:
        return {"passed": False, "score": 0, "feedback": "System error: Task metadata missing targets"}

    # 2. Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Scoring
    total_score = 0
    feedback_lines = []
    
    papers_data = result.get('papers', [])
    papers_map = {p['target_key']: p for p in papers_data}

    for target in targets:
        key = target['title_fragment']
        expected_y = target['expected_year']
        expected_m = target['expected_month']
        expected_d = target['expected_day']
        
        paper_result = papers_map.get(key)
        
        if not paper_result or not paper_result.get('found'):
            feedback_lines.append(f"❌ '{key}': Paper not found in library.")
            continue

        # Anti-gaming check: Was it modified?
        if not paper_result.get('modified_during_task'):
            feedback_lines.append(f"❌ '{key}': Item not modified during task.")
            continue

        raw_date = paper_result.get('date_value')
        y, m, d = parse_date(raw_date)

        if y != expected_y:
            feedback_lines.append(f"❌ '{key}': Wrong year. Expected {expected_y}, got {y} (Raw: '{raw_date}')")
            continue

        # Score calculation for this paper
        paper_score = 0
        status_msg = ""
        
        # Month check (Partial credit base)
        if m == expected_m:
            paper_score += 15
            status_msg = "Correct Month"
            
            # Day check (Full credit)
            if d == expected_d:
                paper_score += 10
                status_msg = "Perfect Match"
            else:
                status_msg += f", Wrong Day (Exp: {expected_d}, Got: {d})"
        else:
            status_msg = f"Wrong Month (Exp: {expected_m}, Got: {m})"

        total_score += paper_score
        feedback_lines.append(f"✅ '{key}': {status_msg} (+{paper_score} pts)")

    # 4. Final Verdict
    passed = total_score >= 60
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": "\n".join(feedback_lines)
    }