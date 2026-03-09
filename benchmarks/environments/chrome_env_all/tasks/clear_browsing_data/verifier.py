#!/usr/bin/env python3
"""
Verifier for Chrome Clear Browsing Data task
Checks that recent browsing history was deleted while old history and other data were preserved
"""

import sys
import os
import sqlite3
import json
from datetime import datetime, timedelta
from pathlib import Path

# Add utils to path
sys.path.insert(0, "/workspace/utils")
from chrome_verification_utils import (
    copy_chrome_file,
    parse_bookmarks,
    cleanup_verification_temp,
    setup_chrome_verification
)


def datetime_to_chrome_timestamp(dt):
    """Convert datetime to Chrome WebKit timestamp (microseconds since Jan 1, 1601)"""
    epoch_start = datetime(1601, 1, 1)
    delta = dt - epoch_start
    return int(delta.total_seconds() * 1000000)


def chrome_timestamp_to_datetime(timestamp):
    """Convert Chrome WebKit timestamp to datetime"""
    epoch_start = datetime(1601, 1, 1)
    return epoch_start + timedelta(microseconds=timestamp)


def parse_history_by_time(history_path, cutoff_hours=1):
    """
    Parse Chrome history and separate entries by time
    
    Args:
        history_path: Path to History database
        cutoff_hours: Hours ago to use as cutoff (entries newer than this are "recent")
    
    Returns:
        Dict with 'recent' (should be deleted) and 'old' (should remain) entry lists
    """
    try:
        # Calculate cutoff timestamp
        now = datetime.now()
        cutoff_time = now - timedelta(hours=cutoff_hours)
        cutoff_timestamp = datetime_to_chrome_timestamp(cutoff_time)
        
        # Connect to database
        conn = sqlite3.connect(history_path)
        cursor = conn.cursor()
        
        # Get all URLs with timestamps
        cursor.execute("""
            SELECT url, title, last_visit_time, visit_count
            FROM urls
            ORDER BY last_visit_time DESC
        """)
        
        results = cursor.fetchall()
        conn.close()
        
        # Separate into recent and old
        recent_entries = []
        old_entries = []
        
        for url, title, last_visit_time, visit_count in results:
            try:
                visit_dt = chrome_timestamp_to_datetime(last_visit_time)
                entry = {
                    'url': url,
                    'title': title,
                    'timestamp': last_visit_time,
                    'datetime': visit_dt.isoformat(),
                    'visit_count': visit_count
                }
                
                if last_visit_time > cutoff_timestamp:
                    recent_entries.append(entry)
                else:
                    old_entries.append(entry)
            except Exception as e:
                print(f"Warning: Could not process entry {url}: {e}")
                continue
        
        return {
            'recent': recent_entries,
            'old': old_entries,
            'total': len(results),
            'cutoff_timestamp': cutoff_timestamp,
            'cutoff_hours': cutoff_hours
        }
    
    except Exception as e:
        print(f"Error parsing history: {e}")
        return None


def verify_history_selective_deletion(history_path, expected_old_count=5):
    """
    Verify that recent history was deleted but old history remains
    
    Args:
        history_path: Path to History database after task
        expected_old_count: Expected number of old entries that should remain
    
    Returns:
        Tuple of (success, details_dict)
    """
    analysis = parse_history_by_time(history_path, cutoff_hours=1)
    
    if analysis is None:
        return False, {"error": "Could not parse history database"}
    
    recent_count = len(analysis['recent'])
    old_count = len(analysis['old'])
    total_count = analysis['total']
    
    # Check criteria
    # 1. Recent entries should be deleted (0 or very few remaining)
    recent_deleted = recent_count == 0
    
    # 2. Old entries should be preserved (at least some should remain)
    old_preserved = old_count >= 3  # At least 3 of the 5 old entries should remain
    
    # 3. Total entries should be less than original (9 total were created)
    history_reduced = total_count < 9
    
    details = {
        'recent_entries_remaining': recent_count,
        'old_entries_remaining': old_count,
        'total_entries': total_count,
        'recent_deleted': recent_deleted,
        'old_preserved': old_preserved,
        'history_reduced': history_reduced,
        'recent_urls': [e['url'] for e in analysis['recent']],
        'old_urls': [e['url'] for e in analysis['old']],
    }
    
    success = recent_deleted and old_preserved and history_reduced
    
    return success, details


def verify_bookmarks_preserved(bookmarks_path):
    """Verify that bookmarks were not affected"""
    try:
        bookmarks = parse_bookmarks(bookmarks_path)
        if not bookmarks:
            return False, "Could not read bookmarks"
        
        # Check that bookmark bar has at least one bookmark
        bookmark_bar = bookmarks.get('roots', {}).get('bookmark_bar', {})
        children = bookmark_bar.get('children', [])
        
        has_bookmarks = len(children) > 0
        
        return has_bookmarks, f"Bookmarks count: {len(children)}"
    
    except Exception as e:
        return False, f"Error checking bookmarks: {e}"


def check_database_integrity(history_path):
    """Verify History database is valid and readable"""
    try:
        conn = sqlite3.connect(history_path)
        cursor = conn.cursor()
        
        # Try basic query
        cursor.execute("SELECT COUNT(*) FROM urls")
        count = cursor.fetchone()[0]
        
        # Check tables exist
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
        tables = [row[0] for row in cursor.fetchall()]
        
        conn.close()
        
        required_tables = ['urls', 'visits']
        has_tables = all(table in tables for table in required_tables)
        
        return has_tables, f"Database valid with {count} URLs and {len(tables)} tables"
    
    except Exception as e:
        return False, f"Database integrity check failed: {e}"


def verify_selective_history_deletion(traj, env_info, task_info):
    """
    Main verification function for clear_browsing_data task
    
    Checks:
    1. Recent history (last hour) was deleted
    2. Old history (older than 1 hour) was preserved
    3. Bookmarks were not affected
    4. History database remains valid
    """
    
    copy_from_env = env_info.get('copy_from_env')
    
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available"
        }
    
    print("=" * 60)
    print("VERIFYING: Clear Browsing Data Task")
    print("=" * 60)
    
    # Setup verification by copying necessary files
    files_to_copy = ["History", "Bookmarks"]
    success, file_paths, error = setup_chrome_verification(
        copy_from_env,
        files_to_copy,
        user="ga",
        profile="Default"
    )
    
    if not success:
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to copy Chrome files: {error}"
        }
    
    history_path = file_paths.get("History")
    bookmarks_path = file_paths.get("Bookmarks")
    
    # Initialize criteria results
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    # Criterion 1: Check selective history deletion
    print("\n[1/4] Checking selective history deletion...")
    history_success, history_details = verify_history_selective_deletion(history_path)
    
    if history_success:
        criteria_met += 1
        feedback_parts.append(f"✓ Recent history deleted ({history_details['recent_entries_remaining']} recent, {history_details['old_entries_remaining']} old)")
    else:
        feedback_parts.append(f"✗ History deletion failed: {history_details['recent_entries_remaining']} recent remaining, {history_details['old_entries_remaining']} old")
    
    print(f"   Recent entries remaining: {history_details['recent_entries_remaining']}")
    print(f"   Old entries remaining: {history_details['old_entries_remaining']}")
    print(f"   Total entries: {history_details['total_entries']}")
    
    # Criterion 2: Old history preserved
    print("\n[2/4] Checking old history preservation...")
    if history_details['old_preserved']:
        criteria_met += 1
        feedback_parts.append("✓ Old history preserved")
        print(f"   ✓ Old history preserved ({history_details['old_entries_remaining']} entries)")
    else:
        feedback_parts.append("✗ Old history not properly preserved")
        print(f"   ✗ Not enough old entries ({history_details['old_entries_remaining']})")
    
    # Criterion 3: Bookmarks preserved
    print("\n[3/4] Checking bookmarks preservation...")
    bookmarks_ok, bookmark_msg = verify_bookmarks_preserved(bookmarks_path)
    
    if bookmarks_ok:
        criteria_met += 1
        feedback_parts.append("✓ Bookmarks preserved")
        print(f"   ✓ {bookmark_msg}")
    else:
        feedback_parts.append(f"✗ Bookmarks issue: {bookmark_msg}")
        print(f"   ✗ {bookmark_msg}")
    
    # Criterion 4: Database integrity
    print("\n[4/4] Checking database integrity...")
    db_ok, db_msg = check_database_integrity(history_path)
    
    if db_ok:
        criteria_met += 1
        feedback_parts.append("✓ Database integrity maintained")
        print(f"   ✓ {db_msg}")
    else:
        feedback_parts.append(f"✗ Database issue: {db_msg}")
        print(f"   ✗ {db_msg}")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = criteria_met >= 3  # Need 3/4 criteria for pass (75%)
    
    # Cleanup
    cleanup_verification_temp()
    
    # Generate feedback
    print("\n" + "=" * 60)
    print(f"RESULT: {'PASSED' if passed else 'FAILED'}")
    print(f"Score: {score}/100 ({criteria_met}/{total_criteria} criteria met)")
    print("=" * 60)
    
    feedback = f"Score: {score}/100 ({criteria_met}/{total_criteria} criteria). " + " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "criteria_met": criteria_met,
            "total_criteria": total_criteria,
            "history_analysis": history_details,
            "bookmarks_preserved": bookmarks_ok,
            "database_valid": db_ok
        }
    }
