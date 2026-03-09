#!/usr/bin/env python3
"""
Verifier for Log Evidence Timestamps task
"""

import sys
import os
import re
import json
import logging
import tempfile
from typing import Dict, List, Tuple, Any

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_log_evidence_timestamps(traj, env_info, task_info):
    """
    Verify log evidence timestamps task completion.
    
    Checks:
    1. Log file exists and is readable
    2. Log contains valid timestamps
    3. Timestamps match expected events within tolerance
    4. Timestamps are in chronological order
    5. Bonus: Snapshots captured
    
    Ground truth events:
    - 5s: Red vehicle
    - 12s: Blue vehicle
    - 18s: Collision
    - 25s: Emergency vehicle
    - 32s: People exit
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Ground truth: (timestamp_seconds, description_keywords)
    TRUE_EVENTS = [
        (5.0, ["red", "vehicle", "car", "enters"]),
        (12.0, ["blue", "vehicle", "car", "enters"]),
        (18.0, ["collision", "incident", "crash", "impact", "occurs"]),
        (25.0, ["emergency", "ambulance", "white", "arrives"]),
        (32.0, ["people", "exit", "person", "individuals", "vehicles"])
    ]
    
    TOLERANCE_SEC = 2.0  # ±2 seconds tolerance
    
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    # === Criterion 1: Check for log file existence ===
    temp_log = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
    
    try:
        copy_from_env("/tmp/vlc_evidence_log.txt", temp_log.name)
    except Exception as e:
        logger.error(f"Error copying log file: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "❌ No timestamp log file found.\n"
                "Expected: /home/ga/Documents/evidence_log.txt\n"
                "Please create a log file documenting the event timestamps."
            )
        }
    
    # Read log content
    try:
        with open(temp_log.name, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
    except Exception as e:
        os.unlink(temp_log.name)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Error reading log file: {e}"
        }
    
    if not content or len(content.strip()) < 10:
        os.unlink(temp_log.name)
        return {
            "passed": False,
            "score": 0.1,
            "feedback": "❌ Log file exists but appears empty or too short"
        }
    
    criteria_met += 1
    feedback_parts.append("✅ Log file exists and readable")
    
    logger.info(f"Log file content ({len(content)} chars):\n{content[:500]}")
    
    # === Criterion 2: Parse timestamps ===
    # Support formats: HH:MM:SS, MM:SS, MM:SS.mmm, M:SS, 0:05, 00:12, etc.
    timestamp_pattern = r'(?:(\d{1,2}):)?(\d{1,2}):(\d{2})(?:[.,](\d{1,3}))?'
    matches = re.findall(timestamp_pattern, content)
    
    if not matches:
        os.unlink(temp_log.name)
        return {
            "passed": False,
            "score": 0.2,
            "feedback": (
                "❌ No valid timestamps found in log file.\n"
                "Expected format: MM:SS or HH:MM:SS (e.g., '00:05' or '0:05')\n"
                f"Log content preview:\n{content[:300]}"
            )
        }
    
    # Convert matches to seconds
    found_timestamps = []
    for match in matches:
        hours = int(match[0]) if match[0] else 0
        minutes = int(match[1])
        seconds = int(match[2])
        millis = int(match[3].ljust(3, '0')[:3]) if match[3] else 0
        
        total_seconds = hours * 3600 + minutes * 60 + seconds + millis / 1000.0
        
        # Only include timestamps in reasonable range (0-40 seconds for our video)
        if 0 <= total_seconds <= 40:
            found_timestamps.append(total_seconds)
    
    logger.info(f"Found timestamps (seconds): {found_timestamps}")
    
    if len(found_timestamps) < 3:
        os.unlink(temp_log.name)
        return {
            "passed": False,
            "score": 0.3,
            "feedback": (
                f"❌ Only found {len(found_timestamps)} valid timestamp(s).\n"
                "Expected at least 4 events to be logged.\n"
                f"Found: {[f'{int(t):02d}s' for t in found_timestamps]}"
            )
        }
    
    criteria_met += 1
    feedback_parts.append(f"✅ Found {len(found_timestamps)} timestamp(s)")
    
    # === Criterion 3: Check chronological order ===
    if found_timestamps == sorted(found_timestamps):
        criteria_met += 1
        feedback_parts.append("✅ Timestamps in chronological order")
    else:
        feedback_parts.append(
            f"⚠️ Timestamps not in chronological order\n"
            f"   Found: {[f'{int(t):02d}s' for t in found_timestamps]}\n"
            f"   Expected: {[f'{int(t):02d}s' for t in sorted(found_timestamps)]}"
        )
    
    # === Criterion 4: Match found timestamps to true events ===
    matched_events = 0
    unmatched_true = []
    match_details = []
    
    used_timestamps = set()
    
    for true_time, keywords in TRUE_EVENTS:
        # Find closest unused timestamp in user's log
        available_timestamps = [t for t in found_timestamps if t not in used_timestamps]
        
        if not available_timestamps:
            unmatched_true.append(f"  ✗ Event at {int(true_time):02d}s: No more timestamps available")
            continue
        
        closest_found = min(available_timestamps, key=lambda t: abs(t - true_time))
        diff = abs(closest_found - true_time)
        
        if diff <= TOLERANCE_SEC:
            matched_events += 1
            used_timestamps.add(closest_found)
            match_details.append(
                f"  ✓ Event at {int(true_time):02d}s matched "
                f"(logged as {int(closest_found):02d}s, diff={diff:.1f}s)"
            )
        else:
            unmatched_true.append(
                f"  ✗ Event at {int(true_time):02d}s NOT matched "
                f"(closest was {int(closest_found):02d}s, diff={diff:.1f}s > {TOLERANCE_SEC}s)"
            )
    
    # Award points based on matched events
    if matched_events >= 4:
        criteria_met += 1
        feedback_parts.append(f"✅ Matched {matched_events}/{len(TRUE_EVENTS)} events")
    elif matched_events >= 3:
        criteria_met += 0.7
        feedback_parts.append(f"⚠️ Matched {matched_events}/{len(TRUE_EVENTS)} events (need 4+)")
    else:
        feedback_parts.append(f"❌ Only matched {matched_events}/{len(TRUE_EVENTS)} events")
    
    # === Criterion 5 (Bonus): Check for snapshots ===
    snapshot_bonus = 0.0
    snapshot_feedback = []
    
    try:
        temp_summary = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        copy_from_env("/tmp/vlc_evidence_summary.json", temp_summary.name)
        
        with open(temp_summary.name, 'r') as f:
            summary = json.load(f)
        
        snapshot_count = summary.get('snapshot_count', 0)
        
        if snapshot_count >= 3:
            snapshot_bonus = 0.15
            snapshot_feedback.append(f"✨ BONUS: {snapshot_count} snapshot(s) captured (+{snapshot_bonus:.2f})")
        elif snapshot_count > 0:
            snapshot_bonus = 0.05
            snapshot_feedback.append(f"⭐ Partial bonus: {snapshot_count} snapshot(s) (+{snapshot_bonus:.2f}, need 3+ for full)")
        
        os.unlink(temp_summary.name)
    except Exception as e:
        logger.warning(f"Could not check snapshots: {e}")
    
    # Clean up
    os.unlink(temp_log.name)
    
    # === Calculate final score and success ===
    base_score = criteria_met / total_criteria
    final_score = min(1.0, base_score + snapshot_bonus)
    
    # Success requires at least 4/5 events matched
    success = matched_events >= 4
    
    # === Build detailed feedback ===
    feedback_lines = [
        "=" * 60,
        f"{'✅ PASSED' if success else '❌ FAILED'} - Evidence Timestamp Logging",
        "=" * 60,
        "",
        "Summary:",
        f"  • Matched Events: {matched_events}/{len(TRUE_EVENTS)}",
        f"  • Timestamps Found: {len(found_timestamps)}",
        f"  • Chronological Order: {'Yes' if found_timestamps == sorted(found_timestamps) else 'No'}",
        f"  • Accuracy: {matched_events/len(TRUE_EVENTS)*100:.0f}%",
        "",
        "Event Matching Details:",
        "-" * 60
    ]
    
    feedback_lines.extend(match_details)
    
    if unmatched_true:
        feedback_lines.append("")
        feedback_lines.append("Unmatched Events:")
        feedback_lines.extend(unmatched_true)
    
    if snapshot_feedback:
        feedback_lines.append("")
        feedback_lines.extend(snapshot_feedback)
    
    feedback_lines.extend([
        "",
        "=" * 60,
        f"Final Score: {final_score:.2f}/1.00 ({int(final_score*100)}%)"
    ])
    
    return {
        "passed": success,
        "score": int(final_score * 100),
        "feedback": "\n".join(feedback_lines),
        "metrics": {
            "events_matched": matched_events,
            "events_total": len(TRUE_EVENTS),
            "timestamps_found": len(found_timestamps),
            "accuracy": matched_events / len(TRUE_EVENTS),
            "snapshots_found": snapshot_count if 'snapshot_count' in locals() else 0,
            "chronological_order": found_timestamps == sorted(found_timestamps),
            "bonus_awarded": snapshot_bonus
        }
    }
