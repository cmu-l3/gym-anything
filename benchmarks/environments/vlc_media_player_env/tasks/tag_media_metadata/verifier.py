#!/usr/bin/env python3
"""
Verifier for Tag Media Metadata task
"""

import sys
import os
import logging
import tempfile
import shutil
import json
import subprocess
from pathlib import Path
from typing import Dict, Any, Tuple

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def extract_metadata_with_ffprobe(filepath: str) -> Dict[str, Any]:
    """
    Extract metadata from video file using ffprobe.
    
    Args:
        filepath: Path to video file
        
    Returns:
        Dict with metadata tags (normalized to lowercase keys)
    """
    try:
        cmd = [
            'ffprobe',
            '-v', 'error',
            '-show_entries', 'format_tags',
            '-of', 'json',
            filepath
        ]
        
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        
        if result.returncode != 0:
            logger.error(f"ffprobe failed: {result.stderr}")
            return {}
        
        data = json.loads(result.stdout)
        
        # Extract tags (case-insensitive keys)
        tags = {}
        if 'format' in data and 'tags' in data['format']:
            raw_tags = data['format']['tags']
            # Normalize keys to lowercase for case-insensitive comparison
            tags = {k.lower(): v for k, v in raw_tags.items()}
        
        return tags
        
    except subprocess.TimeoutExpired:
        logger.error("ffprobe timeout")
        return {}
    except Exception as e:
        logger.error(f"Error extracting metadata: {e}")
        return {}


def verify_tag_metadata(traj, env_info, task_info):
    """
    Verify tag media metadata task completion.
    
    Checks:
    1. Video file exists and can be copied
    2. Metadata fields are present and correct
    3. Minimum 6 out of 8 fields correctly populated
    
    Expected metadata:
    - Title: "Live at The Roxy Theatre"
    - Artist: "The Midnight Riders"
    - Album: "2024 North American Tour"
    - Date: "2024-03-15" (or "2024")
    - Genre: "Rock"
    - Description: Keywords "guitar solos" and "encore"
    - Copyright: Keywords "Personal Recording" or "Non-Commercial"
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Expected metadata
    expected_metadata = {
        'title': 'Live at The Roxy Theatre',
        'artist': 'The Midnight Riders',
        'album': '2024 North American Tour',
        'date': '2024',  # Date formats vary, accept year
        'genre': 'Rock',
        'description': ['guitar solos', 'encore'],  # Check for keywords
        'copyright': ['Personal Recording', 'Non-Commercial']  # Check for keywords
    }
    
    temp_dir = None
    
    try:
        # Copy file from container
        container_path = '/tmp/vlc_tagged_video.mp4'
        temp_dir = tempfile.mkdtemp(prefix='vlc_metadata_verify_')
        host_file = Path(temp_dir) / 'concert_recording.mp4'
        
        # Copy file from environment
        try:
            copy_from_env(container_path, str(host_file))
        except Exception as e:
            logger.error(f"Failed to copy file: {e}")
            return {"passed": False, "score": 0, "feedback": f"Output file not found: {container_path}"}
        
        if not host_file.exists():
            return {"passed": False, "score": 0, "feedback": f"Output file not found after copy: {container_path}"}
        
        if host_file.stat().st_size == 0:
            return {"passed": False, "score": 0, "feedback": "Output file is empty"}
        
        # Extract metadata using ffprobe
        tags = extract_metadata_with_ffprobe(str(host_file))
        
        if not tags:
            return {"passed": False, "score": 0, "feedback": "No metadata found in video file"}
        
        logger.info(f"Extracted metadata tags: {tags}")
        
        # Score each field
        score = 0.0
        max_score = 8.0
        feedback = []
        
        # Check title
        if 'title' in tags:
            if expected_metadata['title'].lower() in tags['title'].lower():
                score += 1
                feedback.append(f"✅ Title: '{tags['title']}'")
            else:
                feedback.append(f"❌ Title incorrect: got '{tags['title']}', expected '{expected_metadata['title']}'")
        else:
            feedback.append("❌ Title field missing")
        
        # Check artist
        if 'artist' in tags:
            if expected_metadata['artist'].lower() in tags['artist'].lower():
                score += 1
                feedback.append(f"✅ Artist: '{tags['artist']}'")
            else:
                feedback.append(f"❌ Artist incorrect: got '{tags['artist']}', expected '{expected_metadata['artist']}'")
        else:
            feedback.append("❌ Artist field missing")
        
        # Check album
        if 'album' in tags:
            if expected_metadata['album'].lower() in tags['album'].lower():
                score += 1
                feedback.append(f"✅ Album: '{tags['album']}'")
            else:
                feedback.append(f"❌ Album incorrect: got '{tags['album']}', expected '{expected_metadata['album']}'")
        else:
            feedback.append("❌ Album field missing")
        
        # Check date (flexible: accept date or year)
        date_found = False
        for date_key in ['date', 'year', 'creation_time']:
            if date_key in tags:
                if expected_metadata['date'] in tags[date_key]:
                    score += 1
                    feedback.append(f"✅ Date: '{tags[date_key]}'")
                    date_found = True
                    break
        if not date_found:
            feedback.append("❌ Date field missing or incorrect")
        
        # Check genre
        if 'genre' in tags:
            if expected_metadata['genre'].lower() in tags['genre'].lower():
                score += 1
                feedback.append(f"✅ Genre: '{tags['genre']}'")
            else:
                feedback.append(f"❌ Genre incorrect: got '{tags['genre']}', expected '{expected_metadata['genre']}'")
        else:
            feedback.append("❌ Genre field missing")
        
        # Check description (keywords)
        desc_keys = ['description', 'comment', 'synopsis']
        description_found = False
        for desc_key in desc_keys:
            if desc_key in tags:
                desc_text = tags[desc_key].lower()
                keywords_found = [kw for kw in expected_metadata['description'] if kw.lower() in desc_text]
                if len(keywords_found) >= 2:
                    score += 1
                    feedback.append(f"✅ Description contains keywords: {keywords_found}")
                    description_found = True
                    break
                elif len(keywords_found) == 1:
                    score += 0.5
                    feedback.append(f"⚠️ Description partially correct (found: {keywords_found})")
                    description_found = True
                    break
        if not description_found:
            feedback.append("❌ Description field missing or doesn't contain required keywords")
        
        # Check copyright
        copyright_keys = ['copyright', 'license']
        copyright_found = False
        for copy_key in copyright_keys:
            if copy_key in tags:
                copy_text = tags[copy_key].lower()
                keywords_found = [kw for kw in expected_metadata['copyright'] if kw.lower() in copy_text]
                if len(keywords_found) >= 1:
                    score += 1
                    feedback.append(f"✅ Copyright contains keywords: {keywords_found}")
                    copyright_found = True
                    break
        if not copyright_found:
            feedback.append("❌ Copyright field missing")
        
        # Calculate final score and success
        normalized_score = (score / max_score) * 100
        success = score >= 6.0  # At least 6/8 fields correct
        
        feedback_str = " | ".join(feedback)
        feedback_str += f" | Score: {score:.1f}/{max_score}"
        
        if success:
            feedback_str += " | ✅ SUCCESS"
        else:
            feedback_str += f" | ❌ FAILURE: Need 6+ fields, got {score:.1f}"
        
        return {
            "passed": success,
            "score": int(normalized_score),
            "feedback": feedback_str
        }
        
    except subprocess.TimeoutExpired:
        return {"passed": False, "score": 0, "feedback": "ffprobe timeout - file may be corrupted"}
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        # Cleanup
        if temp_dir and Path(temp_dir).exists():
            try:
                shutil.rmtree(temp_dir, ignore_errors=True)
            except Exception as e:
                logger.warning(f"Failed to cleanup temp directory: {e}")