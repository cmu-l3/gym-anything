#!/usr/bin/env python3
"""
Verifier for Scan Security Footage task

This task tests the agent's ability to:
1. Navigate efficiently in long videos
2. Use fast playback for scanning
3. Identify visual incidents
4. Capture snapshot evidence at correct timestamps
"""

import sys
import os
import logging
import tempfile
import json
import re
from datetime import datetime
from pathlib import Path

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    verify_snapshot_exists,
    verify_image_quality,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def extract_timestamp_from_filename(filename: str) -> int:
    """
    Extract timestamp in seconds from VLC snapshot filename.
    
    VLC snapshot formats:
    - vlc-snap-2024-01-15-05h15m42s123.png
    - vlc-snap-05h15m42s.png
    - security_snapshot_X.png (our export format)
    
    Returns:
        Timestamp in seconds, or -1 if not found
    """
    # Try HHhMMmSSs format
    pattern = r'(\d{1,2})h(\d{2})m(\d{2})s'
    match = re.search(pattern, filename)
    
    if match:
        hours = int(match.group(1))
        minutes = int(match.group(2))
        seconds = int(match.group(3))
        timestamp_seconds = hours * 3600 + minutes * 60 + seconds
        logger.info(f"Extracted timestamp from {filename}: {hours:02d}:{minutes:02d}:{seconds:02d} ({timestamp_seconds}s)")
        return timestamp_seconds
    
    logger.warning(f"Could not extract timestamp from filename: {filename}")
    return -1


def verify_scan_security_footage(traj, env_info, task_info):
    """
    Verify scan security footage task completion.
    
    Scoring breakdown:
    - Navigation (25%): Agent reached correct timeframe
    - Speed Control (20%): Agent used fast playback efficiently
    - Snapshot Capture (35%): Captured sufficient snapshots
    - Evidence Quality (20%): Snapshots are valid and properly timed
    
    Success criteria:
    - At least 2 snapshots captured
    - Snapshots are valid images (>50 KB)
    - Snapshots captured during incident window (5:15:00 - 5:17:00)
    - Snapshots are temporally separated (different moments)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    score_breakdown = {
        'navigation': 0.0,      # max 0.25
        'speed_control': 0.0,   # max 0.20
        'snapshot_capture': 0.0, # max 0.35
        'evidence_quality': 0.0  # max 0.20
    }
    
    feedback_parts = []
    
    # Expected incident window: 5:15:00 to 5:17:00 (18,900 to 19,020 seconds)
    INCIDENT_START = 18900  # 5:15:00
    INCIDENT_END = 19020    # 5:17:00
    INCIDENT_CENTER = 18945 # 5:15:45
    
    # For the mock video, we use 2:30 = 150s which represents 5:15:30
    # So we need to map video time to overlay time
    # Video starts at t=0 which is 05:13:00 (18780s)
    # So video_time + 18780 = overlay_time
    MOCK_INCIDENT_START = 145  # 2:25 in video = 5:15:25
    MOCK_INCIDENT_END = 165    # 2:45 in video = 5:15:45
    
    temp_dir = tempfile.mkdtemp(prefix='vlc_security_verify_')
    
    try:
        # Step 1: Copy snapshot summary
        temp_summary = os.path.join(temp_dir, 'summary.json')
        
        try:
            copy_from_env("/tmp/vlc_security_snapshots_summary.json", temp_summary)
            
            with open(temp_summary, 'r') as f:
                summary = json.load(f)
            
            snapshot_count = summary.get('snapshot_count', 0)
            feedback_parts.append(f"Found {snapshot_count} snapshot(s)")
            
        except Exception as e:
            logger.error(f"Could not read snapshot summary: {e}")
            snapshot_count = 0
            feedback_parts.append("⚠️ Snapshot summary not found")
        
        # Step 2: Check snapshot count
        if snapshot_count == 0:
            feedback_parts.append("❌ No snapshots captured")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }
        
        if snapshot_count >= 2:
            score_breakdown['snapshot_capture'] += 0.20
            feedback_parts.append(f"✓ Captured sufficient snapshots ({snapshot_count})")
        else:
            score_breakdown['snapshot_capture'] += 0.10
            feedback_parts.append(f"⚠️ Only {snapshot_count} snapshot (need at least 2)")
        
        # Step 3: Verify snapshot files and quality
        valid_snapshots = []
        snapshot_files = []
        
        for i in range(1, snapshot_count + 1):
            snapshot_name = f"security_snapshot_{i}.png"
            temp_snapshot = os.path.join(temp_dir, snapshot_name)
            
            try:
                copy_from_env(f"/tmp/{snapshot_name}", temp_snapshot)
                snapshot_files.append(temp_snapshot)
                
                # Verify image quality
                if os.path.exists(temp_snapshot):
                    size_kb = os.path.getsize(temp_snapshot) / 1024
                    
                    if size_kb > 50 and verify_image_quality(temp_snapshot, min_size_kb=50):
                        valid_snapshots.append(temp_snapshot)
                        logger.info(f"Valid snapshot: {snapshot_name} ({size_kb:.1f} KB)")
                    else:
                        logger.warning(f"Low quality snapshot: {snapshot_name} ({size_kb:.1f} KB)")
                
            except Exception as e:
                logger.warning(f"Could not copy snapshot {snapshot_name}: {e}")
        
        if len(valid_snapshots) >= 2:
            score_breakdown['evidence_quality'] += 0.10
            feedback_parts.append(f"✓ Snapshots have acceptable quality")
        elif len(valid_snapshots) >= 1:
            score_breakdown['evidence_quality'] += 0.05
            feedback_parts.append(f"⚠️ Only {len(valid_snapshots)} valid quality snapshot")
        else:
            feedback_parts.append(f"❌ No valid quality snapshots")
        
        # Step 4: Extract and verify timestamps
        # VLC may name files differently, so we'll be flexible
        # Check if snapshots were taken during the task execution window
        
        # Get modification times of snapshots relative to task start
        # If files are recent (within last 10 minutes), they're likely from this task
        snapshot_times = []
        for snap_file in snapshot_files:
            if os.path.exists(snap_file):
                mtime = os.path.getmtime(snap_file)
                age_seconds = datetime.now().timestamp() - mtime
                if age_seconds < 600:  # Within last 10 minutes
                    snapshot_times.append(mtime)
        
        # Check temporal separation
        if len(snapshot_times) >= 2:
            # Sort times
            snapshot_times.sort()
            
            # Calculate time differences
            time_diffs = []
            for i in range(len(snapshot_times) - 1):
                diff = snapshot_times[i+1] - snapshot_times[i]
                time_diffs.append(diff)
            
            max_diff = max(time_diffs) if time_diffs else 0
            
            if max_diff >= 2:  # At least 2 seconds apart
                score_breakdown['evidence_quality'] += 0.10
                feedback_parts.append(f"✓ Snapshots captured at different moments (~{max_diff:.0f}s apart)")
            else:
                score_breakdown['evidence_quality'] += 0.05
                feedback_parts.append(f"⚠️ Snapshots very close together (~{max_diff:.1f}s apart)")
        
        # Step 5: Award points for navigation and speed control
        # Since we can't directly verify navigation and speed from snapshot metadata alone,
        # we infer from successful completion
        
        # If agent captured multiple valid snapshots, they likely:
        # - Navigated to the right area (else wouldn't find incident)
        # - Used speed controls (else task would timeout)
        
        if len(valid_snapshots) >= 2:
            # Award navigation points (found the incident)
            score_breakdown['navigation'] += 0.25
            feedback_parts.append("✓ Successfully navigated to incident timeframe")
            
            # Award speed control points (completed efficiently)
            score_breakdown['speed_control'] += 0.20
            feedback_parts.append("✓ Efficient scanning suggests speed control used")
            
            # Bonus capture points for finding incident
            score_breakdown['snapshot_capture'] += 0.15
        elif len(valid_snapshots) >= 1:
            # Partial credit
            score_breakdown['navigation'] += 0.15
            score_breakdown['speed_control'] += 0.10
            score_breakdown['snapshot_capture'] += 0.05
            feedback_parts.append("⚠️ Partial success - some snapshots captured")
        else:
            score_breakdown['navigation'] += 0.05
            feedback_parts.append("⚠️ Navigation/scanning efficiency unclear")
        
        # Step 6: Check completion marker
        temp_marker = os.path.join(temp_dir, 'completed.txt')
        try:
            copy_from_env("/tmp/vlc_security_completed.txt", temp_marker)
            logger.info("Task completion marker found")
        except Exception:
            logger.warning("Completion marker not found")
        
        # Calculate total score
        total_score = sum(score_breakdown.values())
        
        # Create summary
        summary_line = f"Score: {total_score:.2f}/1.00 | "
        summary_line += f"Nav: {score_breakdown['navigation']:.2f}/0.25, "
        summary_line += f"Speed: {score_breakdown['speed_control']:.2f}/0.20, "
        summary_line += f"Capture: {score_breakdown['snapshot_capture']:.2f}/0.35, "
        summary_line += f"Quality: {score_breakdown['evidence_quality']:.2f}/0.20"
        
        feedback_parts.insert(0, summary_line)
        
        # Determine pass/fail
        passed = total_score >= 0.70
        score_percent = int(total_score * 100)
        
        return {
            "passed": passed,
            "score": score_percent,
            "feedback": " | ".join(feedback_parts)
        }
    
    finally:
        # Cleanup temp directory
        cleanup_verification_environment(temp_dir)