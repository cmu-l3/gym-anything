#!/usr/bin/env python3
"""
Verifier for Generate Preview Contact Sheet task
"""

import sys
import os
import logging
import tempfile
import shutil
from pathlib import Path

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import verify_image_quality

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_generate_preview_contact_sheet(traj, env_info, task_info):
    """
    Verify generate preview contact sheet task completion.
    
    Checks:
    1. Snapshot count: At least 12/15 snapshots found
    2. Valid images: Snapshots are valid PNG/JPG files with reasonable quality
    3. All videos processed: All 3 videos have preview snapshots
    
    Expected:
    - unknown_01.mp4 (30s): snapshots at ~3s, 9s, 15s, 21s, 27s (10%, 30%, 50%, 70%, 90%)
    - unknown_02.mp4 (40s): snapshots at ~4s, 12s, 20s, 28s, 36s
    - unknown_03.mp4 (50s): snapshots at ~5s, 15s, 25s, 35s, 45s
    """
    copy_from_env = env_info.get('copy_from_env')
    run_command = env_info.get('run_command')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 3
    feedback_parts = []
    
    metadata = {
        'snapshots_found': 0,
        'snapshots_valid': 0,
        'videos_processed': 0,
        'timing_errors': []
    }
    
    # Expected videos and their durations
    expected_videos = {
        'unknown_01': {'duration': 30, 'tolerance': 2},
        'unknown_02': {'duration': 40, 'tolerance': 2},
        'unknown_03': {'duration': 50, 'tolerance': 2}
    }
    
    # Expected snapshot percentages
    expected_percentages = [10, 30, 50, 70, 90]
    tolerance_seconds = 3  # ±3 seconds tolerance for snapshot timing
    
    try:
        # Create temp directory for verification
        temp_dir = tempfile.mkdtemp(prefix='verify_contact_')
        snapshot_dir = Path(temp_dir) / 'contact_sheets'
        snapshot_dir.mkdir(exist_ok=True)
        
        # List files in container's snapshot directory
        if run_command:
            result = run_command("ls -1 /tmp/contact_sheets_export/ 2>/dev/null || echo ''", timeout=5)
            
            if result.get('returncode') == 0 and result.get('stdout', '').strip():
                snapshot_files = [f.strip() for f in result['stdout'].strip().split('\n') if f.strip() and f.strip() != 'no_output.txt']
            else:
                snapshot_files = []
        else:
            # Fallback: try to list directory by copying
            snapshot_files = []
        
        if not snapshot_files:
            shutil.rmtree(temp_dir, ignore_errors=True)
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "❌ No snapshots found in /tmp/contact_sheets_export/",
                "metadata": metadata
            }
        
        metadata['snapshots_found'] = len(snapshot_files)
        
        if len(snapshot_files) < 12:
            feedback_parts.append(f"⚠️ Expected 15 snapshots (5 per video), found {len(snapshot_files)}")
        
        # Copy all snapshots to local temp directory
        for filename in snapshot_files:
            if filename == 'no_output.txt':
                continue
                
            src_path = f"/tmp/contact_sheets_export/{filename}"
            dst_path = snapshot_dir / filename
            try:
                copy_from_env(src_path, str(dst_path))
            except Exception as e:
                feedback_parts.append(f"⚠️ Could not copy {filename}: {e}")
        
        # Verify snapshots for each video
        valid_snapshots_per_video = {}
        
        for video_name, video_info in expected_videos.items():
            video_duration = video_info['duration']
            valid_snapshots_per_video[video_name] = 0
            
            for percentage in expected_percentages:
                expected_time = video_duration * (percentage / 100.0)
                
                # Look for snapshot files matching this video and percentage
                # Check multiple naming patterns
                pattern_matches = []
                
                for f in snapshot_files:
                    if video_name in f.lower():
                        # Check for percentage patterns
                        if f"{percentage}pct" in f.lower() or f"{percentage}percent" in f.lower():
                            pattern_matches.append(f)
                            break
                        
                        # Check for timestamp patterns
                        time_variations = [
                            f"_{int(expected_time)}s",
                            f"_{int(expected_time):02d}s",
                            f"-{int(expected_time)}s",
                            f"-{int(expected_time):02d}s",
                        ]
                        
                        # Check with tolerance
                        for offset in range(-tolerance_seconds, tolerance_seconds + 1):
                            check_time = int(expected_time + offset)
                            if any(f"_{check_time}s" in f or f"-{check_time}s" in f for check_time in [check_time, f"{check_time:02d}"]):
                                pattern_matches.append(f)
                                break
                        
                        if pattern_matches:
                            break
                
                if pattern_matches:
                    # Verify image quality
                    snapshot_path = snapshot_dir / pattern_matches[0]
                    if snapshot_path.exists() and verify_image_quality(str(snapshot_path), min_size_kb=5):
                        valid_snapshots_per_video[video_name] += 1
                        metadata['snapshots_valid'] += 1
                    else:
                        feedback_parts.append(f"⚠️ Snapshot {pattern_matches[0]} has poor quality")
                else:
                    metadata['timing_errors'].append(f"{video_name} missing {percentage}% snapshot")
        
        # Count videos with complete snapshot sets (allow 4/5 for tolerance)
        for video_name, count in valid_snapshots_per_video.items():
            if count >= 4:
                metadata['videos_processed'] += 1
        
        # Criterion 1: Snapshot count (at least 12/15)
        if metadata['snapshots_found'] >= 15:
            criteria_met += 1
            feedback_parts.insert(0, f"✅ All 15 snapshots created")
        elif metadata['snapshots_found'] >= 12:
            criteria_met += 0.7
            feedback_parts.insert(0, f"⚠️ {metadata['snapshots_found']}/15 snapshots created (acceptable)")
        else:
            feedback_parts.insert(0, f"❌ Only {metadata['snapshots_found']}/15 snapshots created")
        
        # Criterion 2: Valid images (at least 12)
        if metadata['snapshots_valid'] >= 15:
            criteria_met += 1
            feedback_parts.append(f"✅ All snapshots are valid images")
        elif metadata['snapshots_valid'] >= 12:
            criteria_met += 0.7
            feedback_parts.append(f"⚠️ {metadata['snapshots_valid']}/15 valid images (acceptable)")
        else:
            feedback_parts.append(f"❌ Only {metadata['snapshots_valid']} valid images")
        
        # Criterion 3: All videos processed
        if metadata['videos_processed'] >= 3:
            criteria_met += 1
            feedback_parts.append(f"✅ All 3 videos processed")
        elif metadata['videos_processed'] >= 2:
            criteria_met += 0.5
            feedback_parts.append(f"⚠️ Only {metadata['videos_processed']}/3 videos processed")
        else:
            feedback_parts.append(f"❌ Only {metadata['videos_processed']}/3 videos processed")
        
        # Success criteria: at least 75% of criteria met
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75
        
        # Build feedback message
        if passed:
            feedback = f"✅ Contact sheet generated successfully!\n"
            feedback += f"   • {metadata['snapshots_found']} snapshots created\n"
            feedback += f"   • {metadata['snapshots_valid']} valid images\n"
            feedback += f"   • {metadata['videos_processed']}/3 videos fully processed"
            if feedback_parts and len(feedback_parts) > 3:
                feedback += f"\n   • Minor issues: {len([p for p in feedback_parts if '⚠️' in p])} warnings"
        else:
            feedback = f"❌ Contact sheet generation incomplete:\n"
            feedback += f"   • Found {metadata['snapshots_found']}/15 expected snapshots\n"
            feedback += f"   • {metadata['snapshots_valid']} valid images\n"
            feedback += f"   • {metadata['videos_processed']}/3 videos fully processed"
            
            if metadata['timing_errors']:
                feedback += f"\n   • Missing snapshots: {len(metadata['timing_errors'])}"
            
            # Add specific feedback
            if feedback_parts:
                feedback += "\n   • " + " | ".join(feedback_parts[:3])
        
        shutil.rmtree(temp_dir, ignore_errors=True)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "metadata": metadata
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"❌ Verification error: {str(e)}",
            "metadata": metadata
        }