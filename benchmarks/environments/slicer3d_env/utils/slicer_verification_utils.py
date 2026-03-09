#!/usr/bin/env python3
"""
Verification utilities for 3D Slicer tasks.
"""

import json
import os
import tempfile
import shutil
from typing import Tuple, Dict, Any, Optional

try:
    from PIL import Image
    HAS_PIL = True
except ImportError:
    HAS_PIL = False


def setup_verification_environment(
    copy_from_env,
    container_path: str,
    file_type: str = 'json'
) -> Tuple[bool, Dict[str, Any], Optional[str]]:
    """
    Set up verification environment by copying file from container.

    Args:
        copy_from_env: Function to copy files from container
        container_path: Path to file in container
        file_type: Type of file ('json', 'image', 'text')

    Returns:
        Tuple of (success, file_info_dict, error_message)
    """
    if not copy_from_env:
        return False, {}, "Copy function not available"

    temp_dir = tempfile.mkdtemp()
    suffix = '.json' if file_type == 'json' else '.png' if file_type == 'image' else '.txt'
    temp_file = os.path.join(temp_dir, f'temp_file{suffix}')

    try:
        copy_from_env(container_path, temp_file)

        file_info = {
            'temp_dir': temp_dir,
            'temp_file': temp_file,
            'file_type': file_type,
            'data': None
        }

        if file_type == 'json':
            with open(temp_file, 'r') as f:
                file_info['data'] = json.load(f)
        elif file_type == 'image':
            if HAS_PIL:
                img = Image.open(temp_file)
                file_info['data'] = {
                    'width': img.width,
                    'height': img.height,
                    'mode': img.mode,
                    'size_kb': os.path.getsize(temp_file) / 1024
                }
                img.close()
            else:
                file_info['data'] = {
                    'size_kb': os.path.getsize(temp_file) / 1024
                }
        elif file_type == 'text':
            with open(temp_file, 'r') as f:
                file_info['data'] = f.read()

        return True, file_info, None

    except Exception as e:
        cleanup_verification_environment(temp_dir)
        return False, {}, str(e)


def cleanup_verification_environment(temp_dir: Optional[str]) -> None:
    """Clean up temporary verification directory."""
    if temp_dir and os.path.exists(temp_dir):
        try:
            shutil.rmtree(temp_dir)
        except Exception:
            pass


def verify_screenshot_quality(
    copy_from_env,
    container_path: str,
    min_size_kb: float = 50,
    min_colors: int = 100
) -> Tuple[bool, Dict[str, Any], str]:
    """
    Verify that a screenshot has reasonable quality.

    Args:
        copy_from_env: Function to copy files from container
        container_path: Path to screenshot in container
        min_size_kb: Minimum file size in KB
        min_colors: Minimum number of unique colors (requires PIL)

    Returns:
        Tuple of (passed, metrics_dict, feedback_string)
    """
    success, file_info, error = setup_verification_environment(
        copy_from_env, container_path, 'image'
    )

    if not success:
        return False, {}, f"Could not read screenshot: {error}"

    try:
        data = file_info.get('data', {})
        size_kb = data.get('size_kb', 0)

        metrics = {
            'size_kb': size_kb,
            'width': data.get('width', 0),
            'height': data.get('height', 0),
        }

        # Check file size
        if size_kb < min_size_kb:
            return False, metrics, f"Screenshot too small ({size_kb:.1f}KB < {min_size_kb}KB)"

        # Check color variety if PIL available
        if HAS_PIL:
            temp_file = file_info.get('temp_file')
            if temp_file:
                img = Image.open(temp_file)
                # Count unique colors (sample for large images)
                if img.width * img.height > 100000:
                    img_small = img.resize((100, 100))
                    colors = len(set(img_small.getdata()))
                else:
                    colors = len(set(img.getdata()))
                metrics['unique_colors'] = colors
                img.close()

                if colors < min_colors:
                    return False, metrics, f"Screenshot may be blank ({colors} colors)"

        return True, metrics, f"Screenshot OK ({size_kb:.1f}KB)"

    finally:
        cleanup_verification_environment(file_info.get('temp_dir'))


def verify_slicer_state(result_data: Dict[str, Any]) -> Tuple[bool, str]:
    """
    Verify that 3D Slicer was in expected state.

    Args:
        result_data: Dictionary from export_result.sh

    Returns:
        Tuple of (passed, feedback_string)
    """
    slicer_running = result_data.get('slicer_was_running', False)
    data_loaded = result_data.get('data_loaded', False)
    screenshot_exists = result_data.get('screenshot_exists', False)

    if not slicer_running:
        return False, "3D Slicer was not running"

    if not screenshot_exists:
        return False, "No screenshot was captured"

    if data_loaded:
        return True, "3D Slicer running with data loaded"

    return True, "3D Slicer running"
