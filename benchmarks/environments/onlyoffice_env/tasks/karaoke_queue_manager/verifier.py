#!/usr/bin/env python3
"""
Verifier for Karaoke Queue Manager task

Checks:
1. Essential columns present (Singer, Song, Status/Order)
2. Adequate queue size (10+ entries)
3. Priority handling (Alex/birthday person in top 4)
4. Fair rotation (repeat singers after first-timers)
5. Status tracking system
6. Time calculations
7. Formatting quality
"""

import sys
import os
import logging
import tempfile
import re
from collections import defaultdict, Counter

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    parse_xlsx_file,
    get_sheet_data,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_text(text):
    """Normalize text for comparison"""
    if text is None:
        return ""
    return str(text).lower().strip()


def find_column_index(headers, keywords):
    """Find column index by matching keywords in header"""
    for idx, header in enumerate(headers):
        header_norm = normalize_text(header)
        if any(keyword in header_norm for keyword in keywords):
            return idx
    return None


def detect_queue_structure(data):
    """
    Detect column structure from spreadsheet data
    Returns dict with column indices: singer, song, status, order, time, length
    """
    structure = {
        'singer_col': None,
        'song_col': None,
        'status_col': None,
        'order_col': None,
        'time_col': None,
        'length_col': None,
        'header_row': None
    }
    
    # Search first 10 rows for headers
    for row_idx in range(min(10, len(data))):
        row = data[row_idx]
        row_text = [normalize_text(cell) for cell in row]
        
        # Check if this looks like a header row
        has_singer = any(kw in ' '.join(row_text) for kw in ['singer', 'name', 'person'])
        has_song = any(kw in ' '.join(row_text) for kw in ['song', 'title', 'track'])
        
        if has_singer and has_song:
            structure['header_row'] = row_idx
            
            # Detect columns
            structure['singer_col'] = find_column_index(row_text, ['singer', 'name', 'person'])
            structure['song_col'] = find_column_index(row_text, ['song', 'title', 'track'])
            structure['status_col'] = find_column_index(row_text, ['status', 'state', 'done', 'complete'])
            structure['order_col'] = find_column_index(row_text, ['queue', 'order', 'position', '#', 'num'])
            structure['time_col'] = find_column_index(row_text, ['running', 'total', 'cumulative'])
            structure['length_col'] = find_column_index(row_text, ['length', 'duration', 'time', 'min'])
            
            break
    
    return structure


def extract_queue_entries(data, structure):
    """Extract queue entries from data based on detected structure"""
    entries = []
    
    if structure['header_row'] is None:
        return entries
    
    start_row = structure['header_row'] + 1
    singer_col = structure['singer_col']
    song_col = structure['song_col']
    
    if singer_col is None or song_col is None:
        return entries
    
    for row_idx in range(start_row, len(data)):
        row = data[row_idx]
        
        if len(row) <= max(singer_col, song_col):
            continue
            
        singer = normalize_text(row[singer_col])
        song = normalize_text(row[song_col])
        
        # Skip empty rows or header-like rows
        if not singer or not song:
            continue
        if any(kw in singer for kw in ['singer', 'name', 'person']):
            continue
            
        entry = {
            'row_idx': row_idx,
            'position': row_idx - start_row,
            'singer': singer,
            'song': song,
            'status': normalize_text(row[structure['status_col']]) if structure['status_col'] is not None and structure['status_col'] < len(row) else "",
            'length': row[structure['length_col']] if structure['length_col'] is not None and structure['length_col'] < len(row) else None
        }
        
        entries.append(entry)
    
    return entries


def check_priority_placement(entries):
    """Check if priority guest (Alex/birthday) is in top 4 positions"""
    priority_keywords = ['alex']
    
    top_4_singers = [e['singer'] for e in entries[:4]]
    
    priority_count = sum(1 for singer in top_4_singers 
                        if any(kw in singer for kw in priority_keywords))
    
    return priority_count >= 2  # Alex should have 2 songs in top 4


def check_fair_rotation(entries):
    """
    Check if repeat singers are placed after first-timers
    Returns (is_fair, ratio, explanation)
    """
    singer_positions = defaultdict(list)
    
    for entry in entries:
        singer_positions[entry['singer']].append(entry['position'])
    
    # Find singers with multiple songs
    repeat_singers = {s: pos for s, pos in singer_positions.items() if len(pos) > 1}
    
    if not repeat_singers:
        return True, 1.0, "No repeat singers to check"
    
    # Count unique first-time singers
    unique_singers = list(singer_positions.keys())
    num_unique = len(unique_singers)
    
    fairness_violations = 0
    total_repeat_checks = 0
    
    for singer, positions in repeat_singers.items():
        # For each repeat performance (2nd, 3rd occurrence)
        for repeat_pos in positions[1:]:
            total_repeat_checks += 1
            
            # Count how many unique singers had their first song AFTER this repeat
            first_timers_after = 0
            for other_singer, other_pos in singer_positions.items():
                if other_singer != singer:
                    # Check if this is their first song and it's after the repeat
                    if other_pos[0] > repeat_pos:
                        first_timers_after += 1
            
            # Violation if there are first-timers placed after repeats
            if first_timers_after > 0:
                fairness_violations += 1
    
    if total_repeat_checks == 0:
        return True, 1.0, "No repeat performances to check"
    
    fairness_ratio = 1.0 - (fairness_violations / total_repeat_checks)
    
    is_fair = fairness_ratio >= 0.7  # Allow some flexibility
    
    explanation = f"Fairness ratio: {fairness_ratio:.2f} ({fairness_violations}/{total_repeat_checks} violations)"
    
    return is_fair, fairness_ratio, explanation


def check_time_tracking(data, structure, entries):
    """Check if time/duration tracking is present and reasonable"""
    has_length = False
    has_running_time = False
    
    # Check if length column has numeric values
    if structure['length_col'] is not None:
        for entry in entries[:5]:  # Check first 5 entries
            if entry['length'] is not None:
                try:
                    val = float(entry['length'])
                    if 2 <= val <= 7:  # Reasonable song length
                        has_length = True
                        break
                except:
                    pass
    
    # Check for running time formulas or values
    if structure['time_col'] is not None:
        start_row = structure['header_row'] + 1
        for row_idx in range(start_row, min(start_row + 10, len(data))):
            if len(data[row_idx]) > structure['time_col']:
                cell_val = data[row_idx][structure['time_col']]
                if cell_val is not None:
                    has_running_time = True
                    break
    
    return has_length or has_running_time


def check_status_system(entries):
    """Check if status tracking system is present"""
    status_values = [e['status'] for e in entries if e['status']]
    
    if not status_values:
        return False, "No status tracking found"
    
    # Check for variety in status values
    unique_statuses = set(status_values)
    
    if len(unique_statuses) == 1:
        return False, f"All entries have same status: {list(unique_statuses)[0]}"
    
    # Check for common status keywords
    status_keywords = ['wait', 'perform', 'done', 'complete', 'current', 'next', 'pending']
    has_status_keywords = any(any(kw in s for kw in status_keywords) for s in status_values)
    
    return True, f"Status system found with {len(unique_statuses)} states"


def verify_karaoke_queue(traj, env_info, task_info):
    """
    Verify karaoke queue organization
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/karaoke_queue.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_karaoke_')
    
    try:
        # Copy file from container
        temp_file = os.path.join(temp_dir, 'karaoke_queue.xlsx')
        
        try:
            copy_from_env(container_path, temp_file)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to copy file: {str(e)}"}
        
        if not os.path.exists(temp_file) or os.path.getsize(temp_file) == 0:
            return {"passed": False, "score": 0, "feedback": f"File not found or empty: {container_path}"}
        
        # Parse spreadsheet
        wb = parse_xlsx_file(temp_file)
        if wb is None:
            return {"passed": False, "score": 0, "feedback": "Failed to parse spreadsheet"}
        
        sheet = wb.active
        data = get_sheet_data(wb, sheet.title, max_rows=50, max_cols=15)
        
        if not data or len(data) < 5:
            return {"passed": False, "score": 0, "feedback": "Spreadsheet appears empty or too small"}
        
        # Detect structure
        structure = detect_queue_structure(data)
        
        criteria_passed = 0
        max_criteria = 9
        feedback_parts = []
        
        # Criterion 1: Essential columns present
        has_singer = structure['singer_col'] is not None
        has_song = structure['song_col'] is not None
        has_organization = structure['order_col'] is not None or structure['status_col'] is not None
        
        if has_singer and has_song and has_organization:
            criteria_passed += 1
            feedback_parts.append("✅ Essential columns present (Singer, Song, Organization)")
        else:
            missing = []
            if not has_singer:
                missing.append("Singer/Name")
            if not has_song:
                missing.append("Song/Title")
            if not has_organization:
                missing.append("Order/Status")
            feedback_parts.append(f"❌ Missing columns: {', '.join(missing)}")
            
            # Cannot continue without basic structure
            return {
                "passed": False,
                "score": int((criteria_passed / max_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        # Extract queue entries
        entries = extract_queue_entries(data, structure)
        
        # Criterion 2: Adequate queue size
        if len(entries) >= 10:
            criteria_passed += 1
            feedback_parts.append(f"✅ Queue has {len(entries)} entries (10+ required)")
        else:
            feedback_parts.append(f"❌ Queue too small: {len(entries)} entries (need 10+)")
        
        if len(entries) < 5:
            # Cannot perform further checks
            return {
                "passed": False,
                "score": int((criteria_passed / max_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        # Criterion 3: Priority guest (Alex) in top 4
        has_priority = check_priority_placement(entries)
        if has_priority:
            criteria_passed += 1
            feedback_parts.append("✅ Priority guest (Alex) has 2 songs in top 4 positions")
        else:
            alex_positions = [i for i, e in enumerate(entries) if 'alex' in e['singer']]
            feedback_parts.append(f"❌ Priority not honored (Alex at positions: {alex_positions})")
        
        # Criterion 4: Fair rotation logic
        is_fair, fairness_ratio, fair_explanation = check_fair_rotation(entries)
        if is_fair:
            criteria_passed += 1
            feedback_parts.append(f"✅ Fair rotation implemented ({fair_explanation})")
        else:
            feedback_parts.append(f"⚠️ Rotation could be fairer ({fair_explanation})")
            # Give partial credit if ratio > 0.5
            if fairness_ratio > 0.5:
                criteria_passed += 0.5
        
        # Criterion 5: Status tracking system
        has_status, status_msg = check_status_system(entries)
        if has_status:
            criteria_passed += 1
            feedback_parts.append(f"✅ Status tracking: {status_msg}")
        else:
            feedback_parts.append(f"❌ Status tracking: {status_msg}")
        
        # Criterion 6: Time tracking
        has_time = check_time_tracking(data, structure, entries)
        if has_time:
            criteria_passed += 1
            feedback_parts.append("✅ Time/duration tracking present")
        else:
            feedback_parts.append("⚠️ No time tracking found")
        
        # Criterion 7: Unique singers identified
        singers = [e['singer'] for e in entries]
        unique_singers = set(singers)
        singer_counts = Counter(singers)
        repeat_singers = [s for s, c in singer_counts.items() if c > 1]
        
        if len(unique_singers) >= 6:
            criteria_passed += 1
            feedback_parts.append(f"✅ {len(unique_singers)} unique singers identified")
        else:
            feedback_parts.append(f"⚠️ Only {len(unique_singers)} unique singers (expected 7-8)")
        
        # Criterion 8: Data completeness
        complete_entries = [e for e in entries if e['singer'] and e['song']]
        completeness_ratio = len(complete_entries) / len(entries) if entries else 0
        
        if completeness_ratio >= 0.9:
            criteria_passed += 1
            feedback_parts.append("✅ Queue data complete (no missing entries)")
        else:
            feedback_parts.append(f"⚠️ Some incomplete entries ({int(completeness_ratio * 100)}% complete)")
        
        # Criterion 9: Practical formatting (check if header row exists and is distinguishable)
        if structure['header_row'] is not None and structure['header_row'] < 10:
            criteria_passed += 1
            feedback_parts.append("✅ Spreadsheet structure is scannable")
        else:
            feedback_parts.append("⚠️ Spreadsheet structure unclear")
        
        # Calculate final score
        score = int((criteria_passed / max_criteria) * 100)
        passed = score >= 70
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_temp_dir(temp_dir)