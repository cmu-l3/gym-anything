#!/usr/bin/env python3
"""
Verifier for Batch Verify Media Integrity task
"""

import sys
import os
import logging
import tempfile
import json
from pathlib import Path

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_batch_verify_media_integrity(traj, env_info, task_info):
    """
    Verify batch verify media integrity task completion.
    
    Checks:
    1. Verified directory exists (10 points)
    2. Correct files copied (50 points):
       - movie_1.mp4 present (15 pts)
       - movie_2.mkv present (15 pts)
       - movie_4.mp4 present (20 pts)
       - Exactly 3 files (penalty for extras)
    3. Corrupted file excluded (20 points):
       - movie_3.avi NOT in verified directory
    4. Verification report created (20 points):
       - File exists (10 pts)
       - Contains movie references (5 pts)
       - Has verification structure (5 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    temp_dir = tempfile.mkdtemp(prefix='vlc_batch_verify_')
    
    try:
        # Criterion 1: Verified directory exists (10 points)
        verified_list_path = Path(temp_dir) / "verified_files_list.txt"
        try:
            copy_from_env("/tmp/verified_files_list.txt", str(verified_list_path))
            
            with open(verified_list_path, 'r') as f:
                file_list = [line.strip() for line in f.readlines() if line.strip()]
            
            if file_list or verified_list_path.stat().st_size >= 0:
                score += 10
                feedback_parts.append("✅ Verified directory created (10/10)")
            else:
                feedback_parts.append("✗ Verified directory not found (0/10)")
        except Exception as e:
            logger.error(f"Error checking verified directory: {e}")
            feedback_parts.append(f"✗ Verified directory not accessible: {e} (0/10)")
            file_list = []
        
        # Criterion 2: Correct files copied (50 points)
        points_earned = 0
        
        # Check for movie_1.mp4
        if "movie_1.mp4" in file_list:
            points_earned += 15
            feedback_parts.append("✅ movie_1.mp4 verified and copied (15/15)")
        else:
            feedback_parts.append("✗ movie_1.mp4 missing from verified directory (0/15)")
        
        # Check for movie_2.mkv
        if "movie_2.mkv" in file_list:
            points_earned += 15
            feedback_parts.append("✅ movie_2.mkv verified and copied (15/15)")
        else:
            feedback_parts.append("✗ movie_2.mkv missing from verified directory (0/15)")
        
        # Check for movie_4.mp4
        if "movie_4.mp4" in file_list:
            points_earned += 20
            feedback_parts.append("✅ movie_4.mp4 verified and copied (20/20)")
        else:
            feedback_parts.append("✗ movie_4.mp4 missing from verified directory (0/20)")
        
        # Check exactly 3 files (deduct if wrong count)
        if len(file_list) == 3:
            feedback_parts.append(f"✅ Exactly 3 files in verified directory (correct)")
        elif len(file_list) > 3:
            penalty = min(10, (len(file_list) - 3) * 5)
            points_earned = max(0, points_earned - penalty)
            feedback_parts.append(f"⚠ Too many files in directory: {len(file_list)} (penalty: -{penalty})")
        elif len(file_list) > 0:
            feedback_parts.append(f"⚠ Only {len(file_list)} files in directory (expected 3)")
        else:
            feedback_parts.append("✗ No files in verified directory (0/50)")
        
        score += points_earned
        
        # Criterion 3: Corrupted file excluded (20 points)
        if file_list:  # Only check if directory has files
            if "movie_3.avi" not in file_list:
                score += 20
                feedback_parts.append("✅ Corrupted file (movie_3.avi) correctly excluded (20/20)")
            else:
                feedback_parts.append("✗ Corrupted file (movie_3.avi) incorrectly included! (0/20)")
        else:
            feedback_parts.append("✗ Cannot verify corrupted file exclusion - no files copied (0/20)")
        
        # Criterion 4: Verification report created (20 points)
        report_path = Path(temp_dir) / "verification_report.txt"
        try:
            copy_from_env("/tmp/verification_report.txt", str(report_path))
            
            if report_path.exists() and report_path.stat().st_size > 0:
                report_points = 10
                feedback_parts.append("✅ Verification report exists (10/10)")
                
                # Check report content
                with open(report_path, 'r') as f:
                    content = f.read().lower()
                
                # Check for movie references
                movie_refs = sum(1 for m in ['movie_1', 'movie_2', 'movie_3', 'movie_4'] 
                               if m in content)
                if movie_refs >= 2:
                    report_points += 5
                    feedback_parts.append("✅ Report mentions movie files (5/5)")
                else:
                    feedback_parts.append("✗ Report lacks movie file references (0/5)")
                
                # Check for structure (working/failed/passed/corrupted keywords)
                structure_keywords = ['working', 'failed', 'passed', 'corrupted', 'verified', 'good', 'bad', 'error']
                if any(kw in content for kw in structure_keywords):
                    report_points += 5
                    feedback_parts.append("✅ Report has verification structure (5/5)")
                else:
                    feedback_parts.append("✗ Report lacks clear verification structure (0/5)")
                
                score += report_points
            else:
                feedback_parts.append("✗ Verification report not found or empty (0/20)")
        except Exception as e:
            logger.error(f"Error checking report: {e}")
            feedback_parts.append(f"✗ Verification report not accessible (0/20)")
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        feedback_parts.append(f"Verification error: {e}")
    finally:
        # Cleanup temp directory
        import shutil
        try:
            shutil.rmtree(temp_dir, ignore_errors=True)
        except:
            pass
    
    # Calculate percentage
    percentage = (score / max_score) * 100
    
    # Overall assessment
    if percentage >= 90:
        overall = "EXCELLENT: All files correctly verified and organized with documentation"
    elif percentage >= 70:
        overall = "PASSING: Files correctly identified and organized"
    elif percentage >= 50:
        overall = "FAILING: Incomplete verification or incorrect file selection"
    else:
        overall = "INSUFFICIENT: Verification task not completed properly"
    
    feedback_parts.insert(0, f"\n{overall}\n")
    
    return {
        "passed": percentage >= 70,
        "score": score,
        "max_score": max_score,
        "percentage": percentage,
        "feedback": '\n'.join(feedback_parts)
    }