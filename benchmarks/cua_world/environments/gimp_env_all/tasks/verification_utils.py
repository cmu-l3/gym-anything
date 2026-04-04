#!/usr/bin/env python3
"""
Shared utilities for GIMP task verification.
Reduces duplicate code across different verifiers.
"""

import tempfile
import logging
import os
from pathlib import Path
from typing import List, Optional, Tuple, Callable

logging.basicConfig(level=logging.DEBUG)

def copy_file_from_container(container_src: str, host_dst: str, copy_from_env_fn: Callable) -> Tuple[bool, str]:
    """Copy file from container to host using the provided copy function."""
    try:
        copy_from_env_fn(container_src, host_dst)
        return True, ""
    except Exception as e:
        return False, f"Failed to copy {container_src}: {str(e)}"


def find_most_recent_file_in_directory(directory_path: str, copy_from_env_fn: Callable, 
                                     file_extensions: List[str] = None) -> Optional[str]:
    """
    Find the most recent file in a directory within the container.
    
    Args:
        directory_path: Path to directory in container
        copy_from_env_fn: Function to copy files from container
        file_extensions: List of allowed extensions (e.g., ['.jpg', '.png', '.jpeg'])
    
    Returns:
        Path to most recent file in container, or None if no suitable file found
    """
    if file_extensions is None:
        file_extensions = ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.tiff']
    
    # Convert extensions to lowercase for comparison
    file_extensions = [ext.lower() for ext in file_extensions]
    
    with tempfile.TemporaryDirectory() as temp_dir:
        temp_path = Path(temp_dir)
        
        # Try to copy a file listing from the directory
        # We'll use a hack - try to copy common filenames and see what exists
        try:
            # Get list of files by attempting to list directory contents
            # This is a bit of a hack since we can't directly list directory contents from container
            
            # Instead, let's try a different approach - look for recently modified files
            # by checking common patterns and timestamps
            
            container_script = f"""
            find {directory_path} -maxdepth 1 -type f -name '*' -printf '%T@ %p\\n' | sort -nr | head -10
            """
            
            # Since we can't easily execute commands, let's try a simpler approach
            # Check for files with common naming patterns and modification times
            
            logging.debug(f"Looking for recent files in {directory_path}")
            
            # For now, return None - this would need container execution capability
            # In practice, the calling verifier should handle the fallback
            return None
            
        except Exception as e:
            logging.debug(f"Could not find recent file in {directory_path}: {e}")
            return None


def find_result_file_with_fallback(possible_results: List[str], copy_from_env_fn: Callable,
                                 fallback_directory: str = "/home/ga/Desktop",
                                 fallback_extensions: List[str] = None) -> Tuple[bool, str, str]:
    """
    Try to find result file from a list of possible names, with fallback to most recent file.
    
    Args:
        possible_results: List of possible result file paths to try
        copy_from_env_fn: Function to copy files from container
        fallback_directory: Directory to search for recent files if none of the predefined names work
        fallback_extensions: Allowed file extensions for fallback search
    
    Returns:
        Tuple of (success, container_path, error_message)
    """
    if fallback_extensions is None:
        fallback_extensions = ['.jpg', '.jpeg', '.png', '.gif', '.bmp']
    
    # First, try all predefined possible results
    for result_path in possible_results:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_file = Path(temp_dir) / "test.tmp"
            success, error = copy_file_from_container(result_path, str(temp_file), copy_from_env_fn)
            if success:
                logging.debug(f"Found result file at: {result_path}")
                return True, result_path, ""
    
    # If none of the predefined names worked, try to find the most recent file
    logging.debug(f"Predefined results not found, searching for recent files in {fallback_directory}")
    
    # Since we can't easily list directory contents from container, let's try some heuristics
    # Look for common patterns of recently created files
    common_patterns = [
        "edited*", "result*", "output*", "final*", "new*", "modified*", "crop*", "resize*", 
        "mirror*", "bright*", "dark*", "color*", "blue*", "red*", "text*", "overlay*"
    ]
    
    # Try to find files matching these patterns
    for pattern in common_patterns:
        for ext in fallback_extensions:
            # Try different variations
            for variant in [f"{pattern}{ext}", f"{pattern.capitalize()}{ext}", f"{pattern.upper()}{ext}"]:
                test_path = f"{fallback_directory}/{variant}"
                with tempfile.TemporaryDirectory() as temp_dir:
                    temp_file = Path(temp_dir) / "test.tmp" 
                    success, error = copy_file_from_container(test_path, str(temp_file), copy_from_env_fn)
                    if success:
                        logging.debug(f"Found fallback result file at: {test_path}")
                        return True, test_path, ""
    
    # If still no luck, return failure with helpful message
    attempted_files = [Path(p).name for p in possible_results]
    return False, "", f"Could not find result file. Tried: {attempted_files}. Also searched for recent files in {fallback_directory}"


def validate_image_file(file_path: str, min_size_bytes: int = 1000) -> Tuple[bool, str]:
    """
    Validate that a file is a proper image file.
    
    Args:
        file_path: Path to image file on host
        min_size_bytes: Minimum file size to consider valid
    
    Returns:
        Tuple of (is_valid, error_message)
    """
    try:
        from PIL import Image
        
        # Check file size
        if not os.path.exists(file_path):
            return False, "File does not exist"
        
        file_size = os.path.getsize(file_path)
        if file_size < min_size_bytes:
            return False, f"File too small ({file_size} bytes, minimum {min_size_bytes})"
        
        # Try to open with PIL
        with Image.open(file_path) as img:
            # Basic validation
            if img.size[0] < 10 or img.size[1] < 10:
                return False, f"Image too small ({img.size})"
            
            # Try to load the image data to catch corruption
            img.load()
            
        return True, ""
        
    except Exception as e:
        return False, f"Invalid image file: {str(e)}"


def setup_verification_environment(original_container_path: str, 
                                 possible_result_paths: List[str],
                                 copy_from_env_fn: Callable,
                                 fallback_directory: str = "/home/ga/Desktop") -> Tuple[bool, dict]:
    """
    Set up the verification environment by copying necessary files from container.
    
    Returns:
        Tuple of (success, file_info_dict)
        file_info_dict contains: {'original_path': str, 'result_path': str, 'temp_dir': str}
    """
    temp_dir = tempfile.mkdtemp()
    temp_path = Path(temp_dir)
    
    try:
        # Copy original file
        host_original = temp_path / "original"
        success, error = copy_file_from_container(original_container_path, str(host_original), copy_from_env_fn)
        if not success:
            return False, {"error": f"Could not access original image: {error}"}
        
        # Validate original file
        valid, error = validate_image_file(str(host_original))
        if not valid:
            return False, {"error": f"Original image invalid: {error}"}
        
        # Find and copy result file
        host_result = temp_path / "result"
        found, result_container_path, error = find_result_file_with_fallback(
            possible_result_paths, copy_from_env_fn, fallback_directory
        )
        
        if not found:
            return False, {"error": error}
        
        # Copy the result file
        success, error = copy_file_from_container(result_container_path, str(host_result), copy_from_env_fn)
        if not success:
            return False, {"error": f"Could not copy result file: {error}"}
        
        # Validate result file
        valid, error = validate_image_file(str(host_result))
        if not valid:
            return False, {"error": f"Result image invalid: {error}"}
        
        return True, {
            "original_path": str(host_original),
            "result_path": str(host_result), 
            "result_container_path": result_container_path,
            "temp_dir": temp_dir
        }
        
    except Exception as e:
        # Clean up on error
        import shutil
        shutil.rmtree(temp_dir, ignore_errors=True)
        return False, {"error": f"Setup failed: {str(e)}"}


# Cleanup function for the temporary directory
def cleanup_verification_environment(temp_dir: str):
    """Clean up temporary directory created during verification."""
    try:
        import shutil
        shutil.rmtree(temp_dir, ignore_errors=True)
    except Exception as e:
        logging.warning(f"Failed to cleanup temp directory {temp_dir}: {e}")
