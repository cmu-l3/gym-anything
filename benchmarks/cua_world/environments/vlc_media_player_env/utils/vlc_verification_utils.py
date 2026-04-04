#!/usr/bin/env python3
"""
VLC verification utilities for gym-anything tasks
Provides helper functions to verify VLC media player tasks
"""

import json
import logging
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import media libraries
try:
    from PIL import Image
    PIL_AVAILABLE = True
except ImportError:
    logger.warning("PIL/Pillow not available - image verification will be limited")
    PIL_AVAILABLE = False

try:
    import cv2
    CV2_AVAILABLE = True
except ImportError:
    logger.warning("OpenCV not available - advanced image verification will be limited")
    CV2_AVAILABLE = False


def get_video_info(filepath: str) -> Dict[str, Any]:
    """
    Get video file information using ffprobe.
    
    Args:
        filepath: Path to video file
        
    Returns:
        Dict with video properties (duration, width, height, codec, etc.)
    """
    try:
        cmd = [
            'ffprobe',
            '-v', 'error',
            '-select_streams', 'v:0',
            '-show_entries', 'stream=codec_name,width,height,duration,bit_rate,r_frame_rate',
            '-show_entries', 'format=duration,size,bit_rate',
            '-of', 'json',
            filepath
        ]
        
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        
        if result.returncode != 0:
            logger.error(f"ffprobe failed: {result.stderr}")
            return {'error': result.stderr}
        
        data = json.loads(result.stdout)
        
        # Extract relevant info
        info = {}
        
        if 'streams' in data and len(data['streams']) > 0:
            stream = data['streams'][0]
            info['codec'] = stream.get('codec_name', '')
            info['width'] = int(stream.get('width', 0))
            info['height'] = int(stream.get('height', 0))
            info['resolution'] = f"{info['width']}x{info['height']}"
            
            # Get duration (prefer stream duration, fall back to format duration)
            duration_str = stream.get('duration') or (data.get('format', {}).get('duration'))
            if duration_str:
                info['duration'] = float(duration_str)
            
            # Get frame rate
            fps_str = stream.get('r_frame_rate', '0/1')
            if '/' in fps_str:
                num, den = map(int, fps_str.split('/'))
                info['fps'] = num / den if den > 0 else 0
            else:
                info['fps'] = float(fps_str)
        
        if 'format' in data:
            fmt = data['format']
            info['format'] = fmt.get('format_name', '')
            info['size_bytes'] = int(fmt.get('size', 0))
            info['bitrate'] = int(fmt.get('bit_rate', 0))
        
        return info
        
    except subprocess.TimeoutExpired:
        logger.error("ffprobe timeout")
        return {'error': 'ffprobe timeout'}
    except Exception as e:
        logger.error(f"Error getting video info: {e}")
        return {'error': str(e)}


def get_audio_info(filepath: str) -> Dict[str, Any]:
    """
    Get audio file information using ffprobe.
    
    Args:
        filepath: Path to audio file
        
    Returns:
        Dict with audio properties (duration, codec, sample_rate, channels, etc.)
    """
    try:
        cmd = [
            'ffprobe',
            '-v', 'error',
            '-select_streams', 'a:0',
            '-show_entries', 'stream=codec_name,sample_rate,channels,duration,bit_rate',
            '-show_entries', 'format=duration,size,bit_rate',
            '-of', 'json',
            filepath
        ]
        
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        
        if result.returncode != 0:
            logger.error(f"ffprobe failed: {result.stderr}")
            return {'error': result.stderr}
        
        data = json.loads(result.stdout)
        
        # Extract relevant info
        info = {}
        
        if 'streams' in data and len(data['streams']) > 0:
            stream = data['streams'][0]
            info['codec'] = stream.get('codec_name', '')
            info['sample_rate'] = int(stream.get('sample_rate', 0))
            info['channels'] = int(stream.get('channels', 0))
            
            # Get duration
            duration_str = stream.get('duration') or (data.get('format', {}).get('duration'))
            if duration_str:
                info['duration'] = float(duration_str)
        
        if 'format' in data:
            fmt = data['format']
            info['format'] = fmt.get('format_name', '')
            info['size_bytes'] = int(fmt.get('size', 0))
            info['bitrate'] = int(fmt.get('bit_rate', 0))
        
        return info
        
    except subprocess.TimeoutExpired:
        logger.error("ffprobe timeout")
        return {'error': 'ffprobe timeout'}
    except Exception as e:
        logger.error(f"Error getting audio info: {e}")
        return {'error': str(e)}


def verify_video_duration(filepath: str, expected_duration: float, tolerance: float = 1.0) -> bool:
    """
    Verify video duration is within expected range.
    
    Args:
        filepath: Path to video file
        expected_duration: Expected duration in seconds
        tolerance: Tolerance in seconds
        
    Returns:
        True if duration matches, False otherwise
    """
    info = get_video_info(filepath)
    
    if 'error' in info:
        logger.error(f"Cannot verify duration: {info['error']}")
        return False
    
    if 'duration' not in info:
        logger.error("Duration not found in video info")
        return False
    
    actual = info['duration']
    return abs(actual - expected_duration) <= tolerance


def verify_video_resolution(filepath: str, expected_width: int, expected_height: int) -> bool:
    """
    Verify video resolution matches expected.
    
    Args:
        filepath: Path to video file
        expected_width: Expected width in pixels
        expected_height: Expected height in pixels
        
    Returns:
        True if resolution matches, False otherwise
    """
    info = get_video_info(filepath)
    
    if 'error' in info:
        logger.error(f"Cannot verify resolution: {info['error']}")
        return False
    
    return info.get('width') == expected_width and info.get('height') == expected_height


def verify_video_codec(filepath: str, expected_codec: str) -> bool:
    """
    Verify video codec matches expected.
    
    Args:
        filepath: Path to video file
        expected_codec: Expected codec name (e.g., 'h264', 'vp9')
        
    Returns:
        True if codec matches, False otherwise
    """
    info = get_video_info(filepath)
    
    if 'error' in info:
        logger.error(f"Cannot verify codec: {info['error']}")
        return False
    
    return info.get('codec', '').lower() == expected_codec.lower()


def parse_m3u_playlist(filepath: str) -> List[str]:
    """
    Parse M3U playlist file.
    
    Args:
        filepath: Path to M3U file
        
    Returns:
        List of media file paths from playlist
    """
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            lines = f.readlines()
        
        items = []
        for line in lines:
            line = line.strip()
            # Skip comments and empty lines
            if not line or line.startswith('#'):
                continue
            items.append(line)
        
        return items
        
    except Exception as e:
        logger.error(f"Error parsing M3U playlist: {e}")
        return []


def parse_xspf_playlist(filepath: str) -> List[Dict[str, str]]:
    """
    Parse XSPF playlist file.
    
    Args:
        filepath: Path to XSPF file
        
    Returns:
        List of dicts with playlist item info
    """
    try:
        import xml.etree.ElementTree as ET
        
        tree = ET.parse(filepath)
        root = tree.getroot()
        
        # XSPF namespace
        ns = {'xspf': 'http://xspf.org/ns/0/'}
        
        items = []
        for track in root.findall('.//xspf:track', ns):
            item = {}
            
            location = track.find('xspf:location', ns)
            if location is not None:
                item['location'] = location.text
            
            title = track.find('xspf:title', ns)
            if title is not None:
                item['title'] = title.text
            
            duration = track.find('xspf:duration', ns)
            if duration is not None:
                item['duration'] = int(duration.text) / 1000.0  # Convert ms to seconds
            
            items.append(item)
        
        return items
        
    except Exception as e:
        logger.error(f"Error parsing XSPF playlist: {e}")
        return []


def parse_vlc_config(filepath: str) -> Dict[str, str]:
    """
    Parse VLC configuration file (vlcrc).
    
    Args:
        filepath: Path to vlcrc file
        
    Returns:
        Dict of config key-value pairs
    """
    try:
        config = {}
        
        with open(filepath, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                
                # Skip comments and empty lines
                if not line or line.startswith('#') or line.startswith('['):
                    continue
                
                # Parse key=value
                if '=' in line:
                    key, value = line.split('=', 1)
                    config[key.strip()] = value.strip()
        
        return config
        
    except Exception as e:
        logger.error(f"Error parsing VLC config: {e}")
        return {}


def get_vlc_volume(config: Dict[str, str]) -> int:
    """
    Get VLC volume from config dict.
    
    Args:
        config: VLC config dict from parse_vlc_config
        
    Returns:
        Volume level (0-512, where 256=100%)
    """
    return int(config.get('audio-volume', 256))


def verify_snapshot_exists(filepath: str, min_size_kb: int = 5) -> bool:
    """
    Verify snapshot file exists and has reasonable size.
    
    Args:
        filepath: Path to snapshot file
        min_size_kb: Minimum file size in KB
        
    Returns:
        True if snapshot is valid, False otherwise
    """
    try:
        if not os.path.exists(filepath):
            logger.error(f"Snapshot not found: {filepath}")
            return False
        
        size_kb = os.path.getsize(filepath) / 1024
        if size_kb < min_size_kb:
            logger.error(f"Snapshot too small: {size_kb:.1f} KB (min: {min_size_kb} KB)")
            return False
        
        # Try to open as image
        if PIL_AVAILABLE:
            try:
                img = Image.open(filepath)
                img.verify()
                logger.info(f"Snapshot valid: {filepath} ({size_kb:.1f} KB, {img.size})")
                return True
            except Exception as e:
                logger.error(f"Invalid image file: {e}")
                return False
        else:
            # Just check size if PIL not available
            logger.warning("PIL not available, only checking file size")
            return True
        
    except Exception as e:
        logger.error(f"Error verifying snapshot: {e}")
        return False


def verify_image_quality(filepath: str, min_size_kb: int = 10) -> bool:
    """
    Verify image quality (size, resolution).
    
    Args:
        filepath: Path to image file
        min_size_kb: Minimum file size in KB
        
    Returns:
        True if image quality is acceptable, False otherwise
    """
    try:
        if not os.path.exists(filepath):
            return False
        
        # Check file size
        size_kb = os.path.getsize(filepath) / 1024
        if size_kb < min_size_kb:
            logger.error(f"Image too small: {size_kb:.1f} KB")
            return False
        
        # Check image properties
        if PIL_AVAILABLE:
            img = Image.open(filepath)
            width, height = img.size
            
            # Minimum resolution check
            if width < 100 or height < 100:
                logger.error(f"Image resolution too low: {width}x{height}")
                return False
            
            logger.info(f"Image quality OK: {size_kb:.1f} KB, {width}x{height}")
            return True
        else:
            # No PIL, just check size
            logger.warning("PIL not available, only checking file size")
            return True
        
    except Exception as e:
        logger.error(f"Error verifying image quality: {e}")
        return False


def copy_and_parse_media(container_path: str, copy_from_env_fn: Callable,
                        file_type: str = 'video') -> Tuple[bool, Dict[str, Any], str, str]:
    """
    Copy media file from container and parse it.
    
    Args:
        container_path: Path to file in container
        copy_from_env_fn: Function to copy files from container
        file_type: Type of file ('video', 'audio', 'image', 'playlist')
        
    Returns:
        Tuple of (success, parsed_data, error_message, temp_dir)
    """
    temp_dir = tempfile.mkdtemp(prefix='vlc_verify_')
    
    try:
        # Copy file from container
        file_ext = Path(container_path).suffix
        host_file = Path(temp_dir) / f"media{file_ext}"
        
        try:
            copy_from_env_fn(container_path, str(host_file))
        except Exception as e:
            shutil.rmtree(temp_dir, ignore_errors=True)
            return False, {}, f"Failed to copy file: {e}", ''
        
        if not host_file.exists() or host_file.stat().st_size == 0:
            shutil.rmtree(temp_dir, ignore_errors=True)
            return False, {}, f"File not found or empty: {container_path}", ''
        
        # Parse based on file type
        data = {}
        
        if file_type == 'video':
            data = get_video_info(str(host_file))
        elif file_type == 'audio':
            data = get_audio_info(str(host_file))
        elif file_type == 'image':
            # For images, just verify and return basic info
            if verify_image_quality(str(host_file)):
                if PIL_AVAILABLE:
                    img = Image.open(str(host_file))
                    data = {
                        'width': img.width,
                        'height': img.height,
                        'format': img.format,
                        'size_kb': host_file.stat().st_size / 1024
                    }
                else:
                    data = {'size_kb': host_file.stat().st_size / 1024}
            else:
                shutil.rmtree(temp_dir, ignore_errors=True)
                return False, {}, "Invalid image file", ''
        elif file_type == 'playlist':
            # Parse playlist
            if file_ext == '.m3u' or file_ext == '.m3u8':
                items = parse_m3u_playlist(str(host_file))
                data = {'items': items, 'count': len(items)}
            elif file_ext == '.xspf':
                items = parse_xspf_playlist(str(host_file))
                data = {'items': items, 'count': len(items)}
            else:
                shutil.rmtree(temp_dir, ignore_errors=True)
                return False, {}, f"Unsupported playlist format: {file_ext}", ''
        
        if 'error' in data:
            shutil.rmtree(temp_dir, ignore_errors=True)
            return False, {}, f"Parse error: {data['error']}", ''
        
        data['filepath'] = str(host_file)
        
        return True, data, "", temp_dir
        
    except Exception as e:
        shutil.rmtree(temp_dir, ignore_errors=True)
        logger.error(f"Error in copy_and_parse_media: {e}")
        return False, {}, str(e), ''


def setup_verification_environment(copy_from_env_fn: Callable, container_path: str,
                                  file_type: str = 'video') -> Tuple[bool, Dict[str, Any], str]:
    """
    Set up verification environment by copying and parsing media file.
    
    Args:
        copy_from_env_fn: Function to copy files from container
        container_path: Path to file in container
        file_type: Type of file ('video', 'audio', 'image', 'playlist')
        
    Returns:
        Tuple of (success, file_info_dict, error_message)
    """
    success, data, error, temp_dir = copy_and_parse_media(container_path, copy_from_env_fn, file_type)
    
    if not success:
        return False, {}, error
    
    file_info = {
        'filepath': data.get('filepath', ''),
        'data': data,
        'temp_dir': temp_dir,
        'file_type': file_type
    }
    
    return True, file_info, ""


def cleanup_verification_environment(temp_dir: Optional[str] = None):
    """
    Clean up temporary verification files.
    
    Args:
        temp_dir: Path to temp directory to clean up
    """
    if temp_dir is None:
        logger.warning("cleanup_verification_environment called with temp_dir=None")
        return
    
    if os.path.exists(temp_dir):
        try:
            shutil.rmtree(temp_dir)
            logger.debug(f"Cleaned up temp directory: {temp_dir}")
        except Exception as e:
            logger.warning(f"Failed to cleanup temp directory {temp_dir}: {e}")


# Alias for compatibility
cleanup_verification_temp = cleanup_verification_environment


def verify_playlist_contents(playlist_path: str, expected_items: List[str],
                            exact_match: bool = False) -> Tuple[bool, str]:
    """
    Verify playlist contains expected items.
    
    Args:
        playlist_path: Path to playlist file
        expected_items: List of expected item paths/names
        exact_match: If True, require exact match; if False, check inclusion
        
    Returns:
        Tuple of (matches, feedback_message)
    """
    try:
        file_ext = Path(playlist_path).suffix.lower()
        
        if file_ext in ['.m3u', '.m3u8']:
            actual_items = parse_m3u_playlist(playlist_path)
        elif file_ext == '.xspf':
            xspf_items = parse_xspf_playlist(playlist_path)
            actual_items = [item.get('location', '') for item in xspf_items]
        else:
            return False, f"Unsupported playlist format: {file_ext}"
        
        if exact_match:
            # Exact match: same items in same order
            if len(actual_items) != len(expected_items):
                return False, f"Item count mismatch: expected {len(expected_items)}, got {len(actual_items)}"
            
            for i, (expected, actual) in enumerate(zip(expected_items, actual_items)):
                # Normalize paths for comparison
                expected_norm = Path(expected).name
                actual_norm = Path(actual).name if actual else ''
                
                if expected_norm not in actual_norm:
                    return False, f"Item {i+1} mismatch: expected {expected_norm}, got {actual_norm}"
            
            return True, f"Playlist matches exactly ({len(actual_items)} items)"
        else:
            # Inclusion match: expected items are present
            missing = []
            for expected in expected_items:
                expected_norm = Path(expected).name
                found = any(expected_norm in Path(actual).name for actual in actual_items if actual)
                if not found:
                    missing.append(expected_norm)
            
            if missing:
                return False, f"Missing items: {', '.join(missing)}"
            
            return True, f"Playlist contains all expected items ({len(expected_items)}/{len(actual_items)})"
        
    except Exception as e:
        logger.error(f"Error verifying playlist: {e}")
        return False, f"Error verifying playlist: {str(e)}"


def check_vlc_process_running() -> bool:
    """
    Check if VLC process is running.
    
    Returns:
        True if VLC is running, False otherwise
    """
    try:
        result = subprocess.run(['pgrep', '-f', 'vlc'], capture_output=True)
        return result.returncode == 0
    except Exception:
        return False
