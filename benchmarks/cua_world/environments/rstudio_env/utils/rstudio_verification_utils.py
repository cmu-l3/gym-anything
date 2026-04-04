#!/usr/bin/env python3
"""Verification utilities for RStudio environment tasks."""

import json
import os
import tempfile
from pathlib import Path
from typing import Dict, Any, Optional, List, Tuple


def setup_verification_environment(copy_from_env, files_to_copy: Dict[str, str]) -> Tuple[Dict[str, Any], List[str]]:
    """
    Copy files from container and set up temp directory for verification.

    Args:
        copy_from_env: Function to copy files from container
        files_to_copy: Dict mapping container paths to local names

    Returns:
        Tuple of (file_info dict, list of error messages)
    """
    temp_dir = tempfile.mkdtemp(prefix="rstudio_verify_")
    file_info = {"temp_dir": temp_dir}
    errors = []

    for container_path, local_name in files_to_copy.items():
        local_path = os.path.join(temp_dir, local_name)
        try:
            copy_from_env(container_path, local_path)
            file_info[local_name] = {
                "path": local_path,
                "exists": True,
                "size": os.path.getsize(local_path)
            }

            # Auto-parse JSON files
            if local_name.endswith('.json'):
                with open(local_path, 'r') as f:
                    file_info[local_name]["data"] = json.load(f)

        except Exception as e:
            file_info[local_name] = {
                "path": local_path,
                "exists": False,
                "error": str(e)
            }
            errors.append(f"Failed to copy {container_path}: {e}")

    return file_info, errors


def cleanup_temp_dir(temp_dir: str) -> None:
    """Clean up temporary directory."""
    import shutil
    try:
        if temp_dir and os.path.exists(temp_dir):
            shutil.rmtree(temp_dir)
    except Exception:
        pass


def verify_csv_file(csv_path: str, required_columns: List[str] = None,
                   min_rows: int = 0) -> Dict[str, Any]:
    """
    Verify a CSV file structure and content.

    Args:
        csv_path: Path to CSV file
        required_columns: List of required column names (case-insensitive)
        min_rows: Minimum number of data rows expected

    Returns:
        Dict with verification results
    """
    result = {
        "exists": False,
        "valid": False,
        "rows": 0,
        "columns": [],
        "missing_columns": [],
        "errors": []
    }

    if not os.path.exists(csv_path):
        result["errors"].append("File does not exist")
        return result

    result["exists"] = True

    try:
        with open(csv_path, 'r') as f:
            lines = f.readlines()

        if not lines:
            result["errors"].append("File is empty")
            return result

        # Parse header
        header = lines[0].strip().lower()
        columns = [col.strip().strip('"\'') for col in header.split(',')]
        result["columns"] = columns
        result["rows"] = len(lines) - 1  # Exclude header

        # Check required columns
        if required_columns:
            required_lower = [c.lower() for c in required_columns]
            for req_col in required_lower:
                found = any(req_col in col for col in columns)
                if not found:
                    result["missing_columns"].append(req_col)

        # Check minimum rows
        if result["rows"] < min_rows:
            result["errors"].append(f"Only {result['rows']} rows, expected at least {min_rows}")

        result["valid"] = (
            len(result["missing_columns"]) == 0 and
            result["rows"] >= min_rows
        )

    except Exception as e:
        result["errors"].append(f"Error parsing CSV: {e}")

    return result


def verify_r_script(script_path: str, required_patterns: List[str] = None) -> Dict[str, Any]:
    """
    Verify an R script contains expected elements.

    Args:
        script_path: Path to R script
        required_patterns: List of strings/patterns that should be in the script

    Returns:
        Dict with verification results
    """
    result = {
        "exists": False,
        "valid": False,
        "size": 0,
        "line_count": 0,
        "patterns_found": {},
        "patterns_missing": [],
        "errors": []
    }

    if not os.path.exists(script_path):
        result["errors"].append("Script does not exist")
        return result

    result["exists"] = True

    try:
        with open(script_path, 'r') as f:
            content = f.read()

        result["size"] = len(content)
        result["line_count"] = len(content.splitlines())

        # Check for patterns
        if required_patterns:
            content_lower = content.lower()
            for pattern in required_patterns:
                found = pattern.lower() in content_lower
                result["patterns_found"][pattern] = found
                if not found:
                    result["patterns_missing"].append(pattern)

        result["valid"] = len(result["patterns_missing"]) == 0

    except Exception as e:
        result["errors"].append(f"Error reading script: {e}")

    return result


def verify_image_file(image_path: str, min_size_kb: int = 5,
                     expected_format: str = None) -> Dict[str, Any]:
    """
    Verify an image file.

    Args:
        image_path: Path to image file
        min_size_kb: Minimum file size in KB
        expected_format: Expected format (PNG, JPEG, etc.)

    Returns:
        Dict with verification results
    """
    result = {
        "exists": False,
        "valid": False,
        "size_kb": 0,
        "dimensions": None,
        "format": None,
        "errors": []
    }

    if not os.path.exists(image_path):
        result["errors"].append("Image does not exist")
        return result

    result["exists"] = True
    result["size_kb"] = os.path.getsize(image_path) // 1024

    try:
        from PIL import Image
        with Image.open(image_path) as img:
            result["dimensions"] = f"{img.width}x{img.height}"
            result["format"] = img.format

        # Validate
        if result["size_kb"] < min_size_kb:
            result["errors"].append(f"Image too small: {result['size_kb']}KB < {min_size_kb}KB")

        if expected_format and result["format"] != expected_format.upper():
            result["errors"].append(f"Wrong format: {result['format']} != {expected_format}")

        result["valid"] = len(result["errors"]) == 0

    except ImportError:
        # PIL not available, use basic checks
        if result["size_kb"] < min_size_kb:
            result["errors"].append(f"Image too small: {result['size_kb']}KB < {min_size_kb}KB")
        result["valid"] = result["size_kb"] >= min_size_kb

    except Exception as e:
        result["errors"].append(f"Error reading image: {e}")

    return result


def calculate_score(criteria: Dict[str, Tuple[bool, int]]) -> Tuple[int, int, List[str]]:
    """
    Calculate total score from criteria dict.

    Args:
        criteria: Dict mapping criterion name to (passed, points) tuple

    Returns:
        Tuple of (score, max_score, feedback_list)
    """
    score = 0
    max_score = 0
    feedback = []

    for name, (passed, points) in criteria.items():
        max_score += points
        if passed:
            score += points
            feedback.append(f"{name}: PASS (+{points})")
        else:
            feedback.append(f"{name}: FAIL (0/{points})")

    return score, max_score, feedback
