#!/usr/bin/env python3
"""
Verification utilities for Weasis DICOM Viewer tasks.
"""

import json
import os
import tempfile
import shutil
from typing import Dict, Any, Optional, Tuple


def setup_verification_environment(
    copy_from_env,
    remote_path: str,
    file_type: str = 'json'
) -> Tuple[bool, Dict[str, Any], Optional[str]]:
    """
    Set up verification environment by copying result file from container.

    Args:
        copy_from_env: Function to copy files from container
        remote_path: Path to file in container
        file_type: Type of file ('json', 'text', 'image')

    Returns:
        Tuple of (success, file_info, error_message)
    """
    temp_dir = tempfile.mkdtemp(prefix="weasis_verify_")
    local_path = os.path.join(temp_dir, os.path.basename(remote_path))

    try:
        copy_from_env(remote_path, local_path)

        if not os.path.exists(local_path):
            return False, {}, f"File not found after copy: {remote_path}"

        file_info = {
            'temp_dir': temp_dir,
            'filepath': local_path,
            'data': None
        }

        if file_type == 'json':
            with open(local_path, 'r') as f:
                file_info['data'] = json.load(f)
        elif file_type == 'text':
            with open(local_path, 'r') as f:
                file_info['data'] = f.read()
        elif file_type == 'image':
            file_info['data'] = {'path': local_path, 'exists': True}

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


def verify_dicom_loaded(result_data: Dict[str, Any], expected_modality: Optional[str] = None) -> Tuple[bool, str]:
    """
    Verify that a DICOM file was loaded successfully.

    Args:
        result_data: Result data from export script
        expected_modality: Expected modality (CT, MR, etc.)

    Returns:
        Tuple of (passed, feedback)
    """
    if not result_data.get('found', False):
        return False, "DICOM file not loaded"

    if expected_modality:
        actual_modality = result_data.get('modality', '').upper()
        if actual_modality != expected_modality.upper():
            return False, f"Wrong modality: expected {expected_modality}, got {actual_modality}"

    return True, "DICOM file loaded successfully"


def verify_window_level_changed(
    result_data: Dict[str, Any],
    initial_wc: float,
    initial_ww: float
) -> Tuple[bool, str]:
    """
    Verify that window/level settings were changed.

    Args:
        result_data: Result data from export script
        initial_wc: Initial window center
        initial_ww: Initial window width

    Returns:
        Tuple of (passed, feedback)
    """
    current_wc = result_data.get('window_center')
    current_ww = result_data.get('window_width')

    if current_wc is None or current_ww is None:
        return False, "Window/level values not found in result"

    # Check if values changed significantly (at least 10% change)
    wc_changed = abs(current_wc - initial_wc) > abs(initial_wc * 0.1) if initial_wc != 0 else current_wc != 0
    ww_changed = abs(current_ww - initial_ww) > abs(initial_ww * 0.1) if initial_ww != 0 else current_ww != 0

    if wc_changed or ww_changed:
        return True, f"Window/level changed: WC={current_wc}, WW={current_ww}"

    return False, f"Window/level not significantly changed (WC={current_wc}, WW={current_ww})"


def verify_measurement_exists(result_data: Dict[str, Any]) -> Tuple[bool, str]:
    """
    Verify that a measurement was made.

    Args:
        result_data: Result data from export script

    Returns:
        Tuple of (passed, feedback)
    """
    measurement = result_data.get('measurement')

    if not measurement:
        return False, "No measurement found"

    # Check for measurement properties
    if isinstance(measurement, dict):
        mtype = measurement.get('type', 'unknown')
        value = measurement.get('value', 0)
        unit = measurement.get('unit', 'px')
        return True, f"Measurement found: {mtype} = {value} {unit}"

    return True, f"Measurement found: {measurement}"


def verify_annotation_exists(result_data: Dict[str, Any]) -> Tuple[bool, str]:
    """
    Verify that an annotation was created.

    Args:
        result_data: Result data from export script

    Returns:
        Tuple of (passed, feedback)
    """
    annotations = result_data.get('annotations', [])

    if not annotations:
        return False, "No annotations found"

    count = len(annotations) if isinstance(annotations, list) else 1
    return True, f"Found {count} annotation(s)"


def verify_zoom_changed(
    result_data: Dict[str, Any],
    initial_zoom: float = 1.0
) -> Tuple[bool, str]:
    """
    Verify that zoom level was changed.

    Args:
        result_data: Result data from export script
        initial_zoom: Initial zoom level

    Returns:
        Tuple of (passed, feedback)
    """
    current_zoom = result_data.get('zoom_level', 1.0)

    if abs(current_zoom - initial_zoom) > 0.1:
        return True, f"Zoom changed to {current_zoom}x"

    return False, f"Zoom not significantly changed (current: {current_zoom}x)"


def verify_export_created(
    copy_from_env,
    export_path: str,
    expected_format: Optional[str] = None
) -> Tuple[bool, str]:
    """
    Verify that an export file was created.

    Args:
        copy_from_env: Function to copy files from container
        export_path: Path to expected export file
        expected_format: Expected file format (jpg, png, etc.)

    Returns:
        Tuple of (passed, feedback)
    """
    temp_dir = tempfile.mkdtemp(prefix="weasis_export_")
    local_path = os.path.join(temp_dir, os.path.basename(export_path))

    try:
        copy_from_env(export_path, local_path)

        if not os.path.exists(local_path):
            cleanup_verification_environment(temp_dir)
            return False, f"Export file not found: {export_path}"

        file_size = os.path.getsize(local_path)
        if file_size == 0:
            cleanup_verification_environment(temp_dir)
            return False, "Export file is empty"

        if expected_format:
            _, ext = os.path.splitext(local_path)
            if ext.lower().lstrip('.') != expected_format.lower():
                cleanup_verification_environment(temp_dir)
                return False, f"Wrong format: expected {expected_format}, got {ext}"

        cleanup_verification_environment(temp_dir)
        return True, f"Export created successfully ({file_size} bytes)"

    except Exception as e:
        cleanup_verification_environment(temp_dir)
        return False, f"Export verification failed: {str(e)}"


def calculate_task_score(criteria_results: list) -> Tuple[int, bool, str]:
    """
    Calculate task score from a list of criteria results.

    Args:
        criteria_results: List of (passed, weight, feedback) tuples

    Returns:
        Tuple of (score, passed, combined_feedback)
    """
    total_weight = sum(weight for _, weight, _ in criteria_results)
    earned_weight = sum(weight for passed, weight, _ in criteria_results if passed)

    score = int((earned_weight / total_weight) * 100) if total_weight > 0 else 0
    passed = score >= 75

    feedback_parts = []
    for criterion_passed, _, feedback in criteria_results:
        prefix = "✅" if criterion_passed else "❌"
        feedback_parts.append(f"{prefix} {feedback}")

    return score, passed, " | ".join(feedback_parts)
