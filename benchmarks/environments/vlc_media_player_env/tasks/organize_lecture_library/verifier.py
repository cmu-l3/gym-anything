#!/usr/bin/env python3
"""
Verifier for Organize Lecture Library task
"""

import sys
import os
import logging
import tempfile
import json
import shutil
from pathlib import Path

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import parse_m3u_playlist

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_organize_lecture_library(traj, env_info, task_info):
    """
    Verify organize lecture library task completion.
    
    Checks:
    1. Folder structure created (Biology101, History202, Math150)
    2. Files are in correct folders
    3. Files follow naming convention
    4. Playlists exist and contain files
    5. Source folder cleaned up
    
    Scoring:
    - Folder structure: 20 points
    - File organization: 40 points
    - Naming convention: 20 points
    - Playlist creation: 15 points
    - Cleanup: 5 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}
    
    scores = {
        'folder_structure': 0.0,
        'file_organization': 0.0,
        'naming_convention': 0.0,
        'playlist_creation': 0.0,
        'cleanup': 0.0
    }
    
    feedback_parts = []
    
    # Create temp directory for verification
    temp_dir = tempfile.mkdtemp(prefix='vlc_organize_verify_')
    
    try:
        # Copy the answer key JSON
        temp_mapping = os.path.join(temp_dir, 'lecture_mapping.json')
        try:
            copy_from_env("/tmp/lecture_mapping.json", temp_mapping)
        except Exception as e:
            logger.error(f"Failed to copy mapping file: {e}")
            return {"passed": False, "score": 0.0, "feedback": f"Error: Could not access answer key: {e}"}
        
        with open(temp_mapping, 'r') as f:
            expected = json.load(f)
        
        # Copy organized structure
        # We need to recursively copy the entire Courses directory
        courses_base = Path(temp_dir) / "Courses"
        courses_base.mkdir(exist_ok=True)
        
        required_folders = ['Biology101', 'History202', 'Math150']
        
        # Try to copy each course folder
        for course_folder in required_folders:
            src_path = f"/home/ga/Videos/Courses/{course_folder}"
            dst_path = courses_base / course_folder
            
            try:
                # Copy directory doesn't work with copy_from_env
                # We need to copy files individually
                # First, try to create the directory by copying a marker file
                
                # Actually, let's try a different approach - copy the entire export structure
                pass
            except Exception as e:
                logger.warning(f"Could not copy {course_folder}: {e}")
        
        # Better approach: copy the exported structure
        export_base = Path(temp_dir) / "export"
        export_base.mkdir(exist_ok=True)
        
        # The export script creates /tmp/organized_lectures/Courses/
        # Let's copy that
        try:
            # We need to list and copy individual files since copy_from_env works on files
            # This is complex, let's use a different strategy
            
            # Copy the summary JSON first
            temp_summary = os.path.join(temp_dir, 'summary.json')
            copy_from_env("/tmp/organization_summary.json", temp_summary)
            
            with open(temp_summary, 'r') as f:
                summary = json.load(f)
            
            if not summary.get('courses_dir_exists', False):
                feedback_parts.append("❌ Courses directory not created")
                return {
                    "passed": False,
                    "score": 0.0,
                    "feedback": " | ".join(feedback_parts)
                }
            
        except Exception as e:
            logger.error(f"Error reading summary: {e}")
            feedback_parts.append(f"⚠️ Could not read organization summary")
        
        # Since we can't easily copy directories, let's check individual files
        # by attempting to copy them based on expected locations
        
        # 1. Check folder structure by attempting to access files
        folders_exist = 0
        for course in required_folders:
            # Try to find any file in this course folder
            course_has_files = False
            
            for file_info in expected['courses'].get(course, []):
                # Try different possible naming patterns
                possible_names = [
                    f"{course}_Week{file_info['week']}_{file_info['topic']}.mp4",
                    f"{course[:4]}_Week{file_info['week']}_{file_info['topic']}.mp4",
                    f"{course.replace('101', '').replace('202', '').replace('150', '')}_Week{file_info['week']}_{file_info['topic']}.mp4",
                ]
                
                for possible_name in possible_names:
                    try:
                        test_path = f"/home/ga/Videos/Courses/{course}/{possible_name}"
                        test_file = os.path.join(temp_dir, f"test_{course}_{file_info['week']}.mp4")
                        copy_from_env(test_path, test_file)
                        
                        if os.path.exists(test_file) and os.path.getsize(test_file) > 1000:
                            course_has_files = True
                            os.unlink(test_file)
                            break
                    except:
                        continue
                
                if course_has_files:
                    break
            
            if course_has_files:
                folders_exist += 1
        
        scores['folder_structure'] = (folders_exist / len(required_folders)) * 20
        if folders_exist == len(required_folders):
            feedback_parts.append(f"✅ Folder structure: {folders_exist}/{len(required_folders)} folders")
        else:
            feedback_parts.append(f"⚠️ Folder structure: {folders_exist}/{len(required_folders)} folders")
        
        # 2. Check file organization and naming
        files_correct = 0
        files_renamed = 0
        total_files = sum(len(v) for v in expected['courses'].values())
        
        for course, files_info in expected['courses'].items():
            for file_info in files_info:
                # Check multiple naming patterns
                patterns_to_check = [
                    f"{course}_Week{file_info['week']}",
                    f"{course[:4]}_Week{file_info['week']}",
                    f"{course.replace('101', '').replace('202', '').replace('150', '')}_Week{file_info['week']}",
                ]
                
                found = False
                for pattern in patterns_to_check:
                    try:
                        # Try to find file with this pattern
                        test_file = os.path.join(temp_dir, f"verify_{course}_{file_info['week']}.mp4")
                        
                        # Generate possible full filenames
                        possible_files = [
                            f"/home/ga/Videos/Courses/{course}/{pattern}_{file_info['topic']}.mp4",
                            f"/home/ga/Videos/Courses/{course}/{pattern}.mp4",
                        ]
                        
                        for possible_file in possible_files:
                            try:
                                copy_from_env(possible_file, test_file)
                                if os.path.exists(test_file) and os.path.getsize(test_file) > 1000:
                                    files_correct += 1
                                    # Check if renamed properly
                                    if '_Week' in os.path.basename(possible_file):
                                        files_renamed += 1
                                    found = True
                                    os.unlink(test_file)
                                    break
                            except:
                                continue
                        
                        if found:
                            break
                    except:
                        continue
        
        scores['file_organization'] = (files_correct / total_files) * 40
        scores['naming_convention'] = (files_renamed / total_files) * 20
        
        feedback_parts.append(f"Files organized: {files_correct}/{total_files}")
        feedback_parts.append(f"Files renamed: {files_renamed}/{total_files}")
        
        # 3. Check playlists
        playlists_valid = 0
        for course in required_folders:
            try:
                playlist_file = os.path.join(temp_dir, f"playlist_{course}.m3u")
                playlist_path = f"/home/ga/Videos/Courses/{course}/playlist.m3u"
                
                copy_from_env(playlist_path, playlist_file)
                
                if os.path.exists(playlist_file) and os.path.getsize(playlist_file) > 10:
                    # Parse playlist
                    items = parse_m3u_playlist(playlist_file)
                    if len(items) >= 2:  # At least 2 entries expected
                        playlists_valid += 1
                    os.unlink(playlist_file)
            except:
                continue
        
        scores['playlist_creation'] = (playlists_valid / len(required_folders)) * 15
        feedback_parts.append(f"Playlists created: {playlists_valid}/{len(required_folders)}")
        
        # 4. Check cleanup
        try:
            # Check if raw folder still has files
            raw_files_remaining = summary.get('raw_files_remaining', 8)
            
            if raw_files_remaining == 0:
                scores['cleanup'] = 5
                feedback_parts.append("✅ Source folder cleaned")
            else:
                feedback_parts.append(f"⚠️ Source folder not cleaned ({raw_files_remaining} files remain)")
        except:
            feedback_parts.append("⚠️ Could not verify cleanup")
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0.0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        # Cleanup temp directory
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
    
    # Calculate total score
    total_score = sum(scores.values())
    passed = total_score >= 80
    
    # Format feedback
    feedback = f"Score: {total_score:.0f}/100 | " + " | ".join(feedback_parts)
    
    logger.info(f"Verification complete: {total_score:.0f}/100, passed={passed}")
    
    return {
        "passed": passed,
        "score": total_score / 100.0,
        "feedback": feedback,
        "details": scores
    }