#!/usr/bin/env python3
"""
Verifier for Batch Media Catalog task
"""

import sys
import os
import re
import logging
import tempfile
from pathlib import Path
from typing import Dict, List, Tuple

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    verify_snapshot_exists,
    verify_image_quality
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_batch_media_catalog(traj, env_info, task_info):
    """
    Verify batch media catalog task completion.
    
    Checks:
    1. Catalog report exists (20 points)
    2. All 4 videos documented in report (20 points)
    3. Duration accuracy for documented videos (20 points)
    4. Resolution accuracy for documented videos (20 points)
    5. Snapshots exist and are valid (20 points)
    
    Pass threshold: 80/100
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Expected values for each video
    expected_specs = {
        'video_01.mp4': {'duration': 45, 'resolution': '1920x1080'},
        'video_02.mkv': {'duration': 62, 'resolution': '1280x720'},
        'video_03.avi': {'duration': 38, 'resolution': '854x480'},
        'video_04.mp4': {'duration': 51, 'resolution': '1920x1080'}
    }
    
    criteria_scores = {
        'report_exists': 0,
        'files_documented': 0,
        'duration_accuracy': 0,
        'resolution_accuracy': 0,
        'snapshots_valid': 0
    }
    
    feedback_parts = []
    
    # Criterion 1: Check if catalog report exists (20 points)
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
    
    try:
        copy_from_env("/tmp/batch_catalog_report.txt", temp_report.name)
    except Exception as e:
        logger.error(f"Error copying catalog report: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Catalog report not found at /home/ga/Documents/media_catalog.txt"
        }
    
    if not os.path.exists(temp_report.name) or os.path.getsize(temp_report.name) == 0:
        os.unlink(temp_report.name)
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Catalog report is empty or invalid"
        }
    
    criteria_scores['report_exists'] = 20
    feedback_parts.append("✅ Catalog report exists")
    
    # Read report content
    with open(temp_report.name, 'r') as f:
        report_content = f.read()
    
    logger.info(f"Report content length: {len(report_content)} characters")
    
    # Criterion 2: Check if all 4 files are documented (20 points)
    files_documented = []
    for filename in expected_specs.keys():
        if filename in report_content:
            files_documented.append(filename)
    
    if len(files_documented) == 4:
        criteria_scores['files_documented'] = 20
        feedback_parts.append("✅ All 4 videos documented")
    elif len(files_documented) > 0:
        criteria_scores['files_documented'] = int((len(files_documented) / 4) * 20)
        feedback_parts.append(f"⚠️  Only {len(files_documented)}/4 videos documented")
    else:
        feedback_parts.append("❌ No videos documented in report")
    
    # Criterion 3: Check duration accuracy (20 points)
    duration_correct = 0
    duration_issues = []
    
    for filename, specs in expected_specs.items():
        if filename not in files_documented:
            continue
        
        # Look for duration in various formats: MM:SS, M:SS, or just seconds
        # Pattern searches for "Duration: XX:YY" or "Duration: XX seconds" near the filename
        pattern = rf"{re.escape(filename)}.*?Duration:\s*(?:(\d{{1,2}}):(\d{{2}})|(\d+)\s*(?:seconds|s|sec))"
        match = re.search(pattern, report_content, re.IGNORECASE | re.DOTALL)
        
        if match:
            if match.group(1) and match.group(2):  # MM:SS format
                minutes = int(match.group(1))
                seconds = int(match.group(2))
                reported_duration = minutes * 60 + seconds
            elif match.group(3):  # Seconds format
                reported_duration = int(match.group(3))
            else:
                continue
            
            expected_duration = specs['duration']
            
            if abs(reported_duration - expected_duration) <= 2:
                duration_correct += 1
            else:
                duration_issues.append(
                    f"{filename}: {reported_duration}s vs {expected_duration}s"
                )
    
    if len(files_documented) > 0:
        duration_score = int((duration_correct / len(files_documented)) * 20)
        criteria_scores['duration_accuracy'] = duration_score
        
        if duration_correct == len(files_documented):
            feedback_parts.append("✅ All durations accurate (±2s)")
        elif duration_correct > 0:
            feedback_parts.append(f"⚠️  {duration_correct}/{len(files_documented)} durations accurate")
        else:
            feedback_parts.append("❌ No accurate durations found")
    
    # Criterion 4: Check resolution accuracy (20 points)
    resolution_correct = 0
    
    for filename, specs in expected_specs.items():
        if filename not in files_documented:
            continue
        
        expected_res = specs['resolution']
        # Look for resolution in format WxH or W x H
        pattern = rf"{re.escape(filename)}.*?Resolution:\s*(\d{{3,4}}\s*[x×]\s*\d{{3,4}})"
        match = re.search(pattern, report_content, re.IGNORECASE | re.DOTALL)
        
        if match:
            reported_res = match.group(1).replace(' ', '').replace('×', 'x').lower()
            expected_res_normalized = expected_res.lower()
            
            if reported_res == expected_res_normalized:
                resolution_correct += 1
    
    if len(files_documented) > 0:
        resolution_score = int((resolution_correct / len(files_documented)) * 20)
        criteria_scores['resolution_accuracy'] = resolution_score
        
        if resolution_correct == len(files_documented):
            feedback_parts.append("✅ All resolutions accurate")
        elif resolution_correct > 0:
            feedback_parts.append(f"⚠️  {resolution_correct}/{len(files_documented)} resolutions accurate")
        else:
            feedback_parts.append("❌ No accurate resolutions found")
    
    # Criterion 5: Check snapshots (20 points)
    snapshot_dir_temp = tempfile.mkdtemp(prefix='batch_catalog_snapshots_')
    valid_snapshots = 0
    
    try:
        # Try to copy snapshot files
        for i in range(1, 5):
            snapshot_name = f"video_0{i}_snapshot.png"
            snapshot_path = os.path.join(snapshot_dir_temp, snapshot_name)
            
            try:
                copy_from_env(f"/tmp/batch_catalog_snapshots/{snapshot_name}", snapshot_path)
                if verify_snapshot_exists(snapshot_path, min_size_kb=50):
                    valid_snapshots += 1
            except:
                # Try alternative naming or locations
                pass
        
        # If named snapshots not found, check for any PNG files
        if valid_snapshots == 0:
            try:
                # Try to get any snapshots from the directory
                import subprocess
                result = subprocess.run(
                    ['find', '/tmp/batch_catalog_snapshots', '-name', '*.png'],
                    capture_output=True, text=True, timeout=5
                )
                if result.stdout:
                    # Count PNG files
                    png_files = [f for f in result.stdout.strip().split('\n') if f]
                    for png_file in png_files[:4]:  # Max 4
                        try:
                            temp_png = os.path.join(snapshot_dir_temp, os.path.basename(png_file))
                            copy_from_env(png_file, temp_png)
                            if verify_snapshot_exists(temp_png, min_size_kb=50):
                                valid_snapshots += 1
                        except:
                            pass
            except:
                pass
        
        snapshot_score = int((valid_snapshots / 4) * 20)
        criteria_scores['snapshots_valid'] = snapshot_score
        
        if valid_snapshots == 4:
            feedback_parts.append("✅ All 4 snapshots valid")
        elif valid_snapshots > 0:
            feedback_parts.append(f"⚠️  Only {valid_snapshots}/4 snapshots valid")
        else:
            feedback_parts.append("❌ No valid snapshots found")
    
    except Exception as e:
        logger.error(f"Error checking snapshots: {e}")
        feedback_parts.append("⚠️  Could not verify snapshots")
    finally:
        # Cleanup
        import shutil
        if os.path.exists(snapshot_dir_temp):
            shutil.rmtree(snapshot_dir_temp, ignore_errors=True)
    
    # Cleanup report temp file
    os.unlink(temp_report.name)
    
    # Calculate total score
    total_score = sum(criteria_scores.values())
    passed = total_score >= 80
    
    feedback_message = " | ".join(feedback_parts)
    feedback_message += f"\n\n📊 Score Breakdown:"
    feedback_message += f"\n  - Report exists: {criteria_scores['report_exists']}/20"
    feedback_message += f"\n  - Files documented: {criteria_scores['files_documented']}/20"
    feedback_message += f"\n  - Duration accuracy: {criteria_scores['duration_accuracy']}/20"
    feedback_message += f"\n  - Resolution accuracy: {criteria_scores['resolution_accuracy']}/20"
    feedback_message += f"\n  - Snapshots valid: {criteria_scores['snapshots_valid']}/20"
    feedback_message += f"\n\n📊 Final Score: {total_score}/100"
    
    if passed:
        feedback_message += "\n🎉 Task completed successfully!"
    else:
        feedback_message += "\n❌ Task incomplete - need 80/100 to pass"
    
    return {
        "passed": passed,
        "score": total_score / 100.0,
        "feedback": feedback_message
    }