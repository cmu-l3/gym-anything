#!/usr/bin/env python3
from __future__ import annotations

import logging
import os
import tempfile
from pathlib import Path
from typing import Callable, List, Optional, Tuple


logging.basicConfig(level=logging.DEBUG)


def copy_file_from_container(container_src: str, host_dst: str, copy_from_env_fn: Callable) -> Tuple[bool, str]:
    try:
        copy_from_env_fn(container_src, host_dst)
        return True, ""
    except Exception as exc:
        return False, f"Failed to copy {container_src}: {exc}"


def validate_image_file(file_path: str, min_size_bytes: int = 1000) -> Tuple[bool, str]:
    try:
        from PIL import Image

        if not os.path.exists(file_path):
            return False, "File does not exist"

        file_size = os.path.getsize(file_path)
        if file_size < min_size_bytes:
            return False, f"File too small ({file_size} bytes, minimum {min_size_bytes})"

        with Image.open(file_path) as img:
            if img.size[0] < 10 or img.size[1] < 10:
                return False, f"Image too small ({img.size})"
            img.load()
        return True, ""
    except Exception as exc:
        return False, f"Invalid image file: {exc}"


def find_result_file_with_fallback(
    possible_results: List[str],
    copy_from_env_fn: Callable,
    fallback_directory: str = "/home/ga/Desktop",
    fallback_extensions: Optional[List[str]] = None,
) -> Tuple[bool, str, str]:
    if fallback_extensions is None:
        fallback_extensions = [".jpg", ".jpeg", ".png", ".gif", ".bmp"]

    for result_path in possible_results:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_file = Path(temp_dir) / "probe.tmp"
            success, error = copy_file_from_container(result_path, str(temp_file), copy_from_env_fn)
            if success:
                logging.debug("Found result file at: %s", result_path)
                return True, result_path, ""
            logging.debug("Probe failed for %s: %s", result_path, error)

    common_patterns = [
        "edited*",
        "result*",
        "output*",
        "final*",
        "new*",
        "modified*",
        "crop*",
        "resize*",
        "mirror*",
        "bright*",
        "dark*",
        "color*",
        "blue*",
        "red*",
        "text*",
        "overlay*",
    ]

    for pattern in common_patterns:
        for ext in fallback_extensions:
            for variant in (f"{pattern}{ext}", f"{pattern.capitalize()}{ext}", f"{pattern.upper()}{ext}"):
                test_path = f"{fallback_directory}/{variant}"
                with tempfile.TemporaryDirectory() as temp_dir:
                    temp_file = Path(temp_dir) / "probe.tmp"
                    success, _ = copy_file_from_container(test_path, str(temp_file), copy_from_env_fn)
                    if success:
                        logging.debug("Found fallback result file at: %s", test_path)
                        return True, test_path, ""

    attempted_files = [Path(p).name for p in possible_results]
    return False, "", f"Could not find result file. Tried: {attempted_files}. Also searched in {fallback_directory}"


def setup_verification_environment(
    original_container_path: str,
    possible_result_paths: List[str],
    copy_from_env_fn: Callable,
    fallback_directory: str = "/home/ga/Desktop",
) -> Tuple[bool, dict]:
    temp_dir = tempfile.mkdtemp()
    temp_path = Path(temp_dir)

    try:
        host_original = temp_path / "original"
        success, error = copy_file_from_container(original_container_path, str(host_original), copy_from_env_fn)
        if not success:
            return False, {"error": f"Could not access original image: {error}"}

        valid, error = validate_image_file(str(host_original))
        if not valid:
            return False, {"error": f"Original image invalid: {error}"}

        host_result = temp_path / "result"
        found, result_container_path, error = find_result_file_with_fallback(
            possible_result_paths,
            copy_from_env_fn,
            fallback_directory,
        )
        if not found:
            return False, {"error": error}

        success, error = copy_file_from_container(result_container_path, str(host_result), copy_from_env_fn)
        if not success:
            return False, {"error": f"Could not copy result file: {error}"}

        valid, error = validate_image_file(str(host_result))
        if not valid:
            return False, {"error": f"Result image invalid: {error}"}

        return True, {
            "original_path": str(host_original),
            "result_path": str(host_result),
            "result_container_path": result_container_path,
            "temp_dir": temp_dir,
        }
    except Exception as exc:
        cleanup_verification_environment(temp_dir)
        return False, {"error": f"Setup failed: {exc}"}


def cleanup_verification_environment(temp_dir: str) -> None:
    try:
        import shutil

        shutil.rmtree(temp_dir, ignore_errors=True)
    except Exception as exc:
        logging.warning("Failed to cleanup temp directory %s: %s", temp_dir, exc)


__all__ = [
    "cleanup_verification_environment",
    "copy_file_from_container",
    "find_result_file_with_fallback",
    "setup_verification_environment",
    "validate_image_file",
]
