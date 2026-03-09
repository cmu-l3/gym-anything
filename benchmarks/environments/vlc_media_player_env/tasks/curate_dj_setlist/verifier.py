#!/usr/bin/env python3
"""
Verifier for DJ Setlist Curation task.

Checks that the playlist contains only high-quality tracks (bitrate >= 192 kbps)
and includes all high-quality tracks (no false negatives).
"""

import sys
import os
import logging
import json
import tempfile
import shutil
from pathlib import Path
from typing import Dict, List, Set, Tuple

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import parse_xspf_playlist, parse_m3u_playlist

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Quality threshold in kbps
QUALITY_THRESHOLD_KBPS = 192

# Expected counts
EXPECTED_HIGH_QUALITY_COUNT = 8  # tracks 01-08
EXPECTED_LOW_QUALITY_COUNT = 7   # tracks 09-15
TOTAL_TRACKS = 15


def get_track_bitrate_from_json(json_path: str) -> float:
    """
    Extract bitrate from ffprobe JSON output.
    
    Args:
        json_path: Path to JSON file with ffprobe output
        
    Returns:
        Bitrate in kbps (0 if not found or lossless format)
    """
    try:
        with open(json_path, 'r') as f:
            data = json.load(f)
        
        if 'streams' in data and len(data['streams']) > 0:
            stream = data['streams'][0]
            
            # Check for lossless formats
            codec = stream.get('codec_name', '').lower()
            if codec in ['flac', 'pcm_s16le', 'pcm_s24le', 'alac', 'wav']:
                # Lossless formats - treat as high quality (CD quality equivalent)
                return 1411.0
            
            # Get bitrate
            bitrate_str = stream.get('bit_rate', '0')
            if bitrate_str and bitrate_str != 'N/A':
                bitrate_bps = int(bitrate_str)
                bitrate_kbps = bitrate_bps / 1000
                return bitrate_kbps
        
        return 0.0
        
    except Exception as e:
        logger.warning(f"Error parsing {json_path}: {e}")
        return 0.0


def get_track_bitrate_from_ground_truth(track_name: str, ground_truth_dir: str) -> float:
    """
    Get track bitrate from ground truth metadata.
    
    Args:
        track_name: Track filename
        ground_truth_dir: Directory with ground truth bitrate files
        
    Returns:
        Bitrate in kbps
    """
    try:
        bitrate_file = os.path.join(ground_truth_dir, f"{track_name}.bitrate")
        if os.path.exists(bitrate_file):
            with open(bitrate_file, 'r') as f:
                return float(f.read().strip())
    except Exception as e:
        logger.warning(f"Error reading ground truth for {track_name}: {e}")
    
    return 0.0


def verify_curate_dj_setlist(traj, env_info, task_info):
    """
    Verify the DJ setlist curation task.
    
    Checks:
    1. Playlist file exists and is valid
    2. All high-quality tracks are included (no false negatives)
    3. No low-quality tracks are included (no false positives)
    4. 100% accuracy in quality assessment
    
    Args:
        traj: Trajectory data
        env_info: Environment info including copy_from_env function
        task_info: Task information
        
    Returns:
        Dict with passed, score, and feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available"
        }
    
    feedback_parts = []
    
    # Create temporary directory for verification
    temp_dir = tempfile.mkdtemp(prefix='vlc_dj_verify_')
    result_dir = os.path.join(temp_dir, 'task_result')
    
    try:
        # Copy entire result directory from container
        logger.info("Copying results from container...")
        try:
            copy_from_env("/tmp/task_result", result_dir)
        except Exception as e:
            logger.error(f"Error copying results: {e}")
            shutil.rmtree(temp_dir, ignore_errors=True)
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to copy results from container: {str(e)}"
            }
        
        # Check if playlist exists
        playlist_path = os.path.join(result_dir, 'approved_setlist.xspf')
        if not os.path.exists(playlist_path):
            # Try M3U format as fallback
            playlist_path = playlist_path.replace('.xspf', '.m3u')
            if not os.path.exists(playlist_path):
                shutil.rmtree(temp_dir, ignore_errors=True)
                return {
                    "passed": False,
                    "score": 0,
                    "feedback": "Playlist file not found at expected location"
                }
        
        feedback_parts.append("✅ Playlist file exists")
        logger.info(f"Playlist found: {playlist_path}")
        
        # Parse playlist
        try:
            if playlist_path.endswith('.xspf'):
                playlist_items = parse_xspf_playlist(playlist_path)
                # Extract locations from XSPF items
                playlist_locations = [item.get('location', '') for item in playlist_items]
            else:
                playlist_locations = parse_m3u_playlist(playlist_path)
            
            if not playlist_locations:
                shutil.rmtree(temp_dir, ignore_errors=True)
                return {
                    "passed": False,
                    "score": 0,
                    "feedback": "Playlist is empty or could not be parsed"
                }
            
            feedback_parts.append(f"Playlist contains {len(playlist_locations)} tracks")
            logger.info(f"Playlist has {len(playlist_locations)} items")
            
        except Exception as e:
            logger.error(f"Error parsing playlist: {e}")
            shutil.rmtree(temp_dir, ignore_errors=True)
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Error parsing playlist: {str(e)}"
            }
        
        # Extract track names from playlist
        included_tracks = set()
        for location in playlist_locations:
            if location:
                # Handle file:// URLs and plain paths
                location_clean = location.replace('file://', '')
                track_name = Path(location_clean).name
                included_tracks.add(track_name)
        
        logger.info(f"Included tracks: {included_tracks}")
        
        # Load track metadata to determine actual quality
        track_info_dir = os.path.join(result_dir, 'track_info')
        ground_truth_dir = os.path.join(result_dir, 'ground_truth_bitrates')
        
        track_qualities: Dict[str, float] = {}
        
        # Get bitrates from JSON metadata
        if os.path.exists(track_info_dir):
            for json_file in Path(track_info_dir).glob('*.json'):
                track_name = json_file.stem  # Filename without .json
                bitrate = get_track_bitrate_from_json(str(json_file))
                
                # Fallback to ground truth if ffprobe failed
                if bitrate == 0.0 and os.path.exists(ground_truth_dir):
                    bitrate = get_track_bitrate_from_ground_truth(track_name, ground_truth_dir)
                
                if bitrate > 0:
                    track_qualities[track_name] = bitrate
                    logger.info(f"{track_name}: {bitrate:.0f} kbps")
        
        if not track_qualities:
            shutil.rmtree(temp_dir, ignore_errors=True)
            return {
                "passed": False,
                "score": 0,
                "feedback": "Could not determine track qualities from metadata"
            }
        
        # Categorize tracks by quality
        high_quality_tracks: Set[str] = set()
        low_quality_tracks: Set[str] = set()
        
        for track_name, bitrate in track_qualities.items():
            if bitrate >= QUALITY_THRESHOLD_KBPS:
                high_quality_tracks.add(track_name)
            else:
                low_quality_tracks.add(track_name)
        
        logger.info(f"High quality tracks ({len(high_quality_tracks)}): {high_quality_tracks}")
        logger.info(f"Low quality tracks ({len(low_quality_tracks)}): {low_quality_tracks}")
        
        # Calculate metrics
        true_positives = len(included_tracks & high_quality_tracks)
        false_positives = len(included_tracks & low_quality_tracks)
        false_negatives = len(high_quality_tracks - included_tracks)
        true_negatives = len(low_quality_tracks - included_tracks)
        
        # Detailed feedback
        if false_positives > 0:
            bad_tracks = included_tracks & low_quality_tracks
            bad_tracks_list = ', '.join(sorted(bad_tracks))
            feedback_parts.append(f"❌ Included {false_positives} low-quality track(s): {bad_tracks_list}")
            logger.warning(f"False positives: {bad_tracks}")
        else:
            feedback_parts.append("✅ No low-quality tracks included")
        
        if false_negatives > 0:
            missed_tracks = high_quality_tracks - included_tracks
            missed_tracks_list = ', '.join(sorted(missed_tracks))
            feedback_parts.append(f"❌ Missing {false_negatives} high-quality track(s): {missed_tracks_list}")
            logger.warning(f"False negatives: {missed_tracks}")
        else:
            feedback_parts.append("✅ All high-quality tracks included")
        
        # Calculate accuracy
        total_decisions = len(track_qualities)
        correct_decisions = true_positives + true_negatives
        accuracy = correct_decisions / total_decisions if total_decisions > 0 else 0.0
        
        feedback_parts.append(f"Accuracy: {accuracy:.1%} ({correct_decisions}/{total_decisions} correct)")
        
        # Success requires 100% accuracy
        success = (false_positives == 0 and false_negatives == 0)
        
        # Score calculation
        # Give partial credit for accuracy
        score = int(accuracy * 100)
        
        if success:
            feedback_parts.append("✅ Perfect curation: All correct!")
            logger.info("✓ Task completed successfully with 100% accuracy")
        else:
            logger.warning(f"Task incomplete. Accuracy: {accuracy:.1%}")
        
        # Clean up
        shutil.rmtree(temp_dir, ignore_errors=True)
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": success,
            "score": score,
            "feedback": feedback,
            "metrics": {
                "true_positives": true_positives,
                "false_positives": false_positives,
                "false_negatives": false_negatives,
                "true_negatives": true_negatives,
                "accuracy": accuracy,
                "total_tracks": total_decisions,
                "included_count": len(included_tracks)
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        shutil.rmtree(temp_dir, ignore_errors=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
