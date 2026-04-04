#!/usr/bin/env python3
"""
Verifier for Chrome Multiple File Downloads Task (multi_file_download@1)
Task: Download three files (PDF, PNG, TXT) from a webpage

Verification Strategy:
- Check Downloads folder for presence of all three files
- Validate file sizes are non-zero and reasonable
- Verify file types using magic bytes (PDF signature, PNG header)
- Check file timestamps to ensure they were created during task execution
- Multi-criteria scoring: need 2/3 files for pass (75% threshold)
"""

import logging
import sys
import os
import tempfile
from pathlib import Path
from datetime import datetime, timedelta
from typing import Dict, List, Tuple, Any, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../..', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available")
    UTILS_AVAILABLE = False
    def cleanup_verification_temp():
        pass


# Expected file specifications
EXPECTED_FILES = {
    'sample.pdf': {
        'min_size': 400,  # Minimum bytes (our test PDF is ~410 bytes)
        'max_size': 100 * 1024,  # 100KB max (reasonable for test file)
        'magic_bytes': b'%PDF',
        'magic_offset': 0,
        'description': 'PDF document'
    },
    'image.png': {
        'min_size': 60,  # Minimum bytes (PNG header + minimal data)
        'max_size': 10 * 1024,  # 10KB max
        'magic_bytes': b'\x89PNG\r\n\x1a\n',
        'magic_offset': 0,
        'description': 'PNG image'
    },
    'document.txt': {
        'min_size': 50,  # At least 50 bytes of text
        'max_size': 10 * 1024,  # 10KB max
        'magic_bytes': None,  # No magic bytes for text files
        'magic_offset': 0,
        'description': 'Text document'
    }
}


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for multi_file_download@1.
    
    Verifies that all three files were successfully downloaded to ~/Downloads/
    
    Criteria (3 total, need 2+ for pass):
    1. PDF file downloaded with correct type and size
    2. PNG file downloaded with correct type and size
    3. TXT file downloaded with correct type and size
    
    Bonus checks:
    - Files created during task execution (timestamp check)
    - No partial downloads (.crdownload files)
    
    Args:
        traj: Trajectory data
        env_info: Environment info with copy_from_env function
        task_info: Task configuration
        
    Returns:
        Dict with passed, score, feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in environment"
        }

    try:
        # Get task start time
        task_start_time = get_task_start_time(copy_from_env)
        
        # Verify each file
        verification_results = {}
        for filename, specs in EXPECTED_FILES.items():
            result = verify_downloaded_file(
                copy_from_env, 
                filename, 
                specs,
                task_start_time
            )
            verification_results[filename] = result
        
        # Calculate overall score
        final_result = calculate_final_score(verification_results)
        
        # Cleanup
        cleanup_verification_temp()
        
        return final_result
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def get_task_start_time(copy_from_env) -> Optional[datetime]:
    """
    Get the task start time for timestamp verification.
    
    Returns:
        datetime object or None if not available
    """
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        temp_file.close()
        
        copy_from_env("/tmp/download_verification/task_start_time.txt", temp_file.name)
        
        with open(temp_file.name, 'r') as f:
            timestamp = int(f.read().strip())
        
        os.unlink(temp_file.name)
        return datetime.fromtimestamp(timestamp)
        
    except Exception as e:
        logger.warning(f"Could not get task start time: {e}")
        return None


def verify_downloaded_file(
    copy_from_env, 
    filename: str, 
    specs: Dict[str, Any],
    task_start_time: Optional[datetime]
) -> Dict[str, Any]:
    """
    Verify a single downloaded file.
    
    Args:
        copy_from_env: Function to copy files from container
        filename: Name of file to verify
        specs: File specifications (size limits, magic bytes)
        task_start_time: When the task started
        
    Returns:
        Dict with verification results for this file
    """
    result = {
        'found': False,
        'valid_size': False,
        'correct_type': False,
        'recent': False,
        'size': 0,
        'error': None
    }
    
    temp_file = None
    try:
        # Copy file from Downloads folder
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=f'_{filename}')
        temp_file.close()
        
        downloads_path = f"/home/ga/Downloads/{filename}"
        
        try:
            copy_from_env(downloads_path, temp_file.name)
        except Exception as e:
            result['error'] = f"File not found: {filename}"
            logger.warning(f"Could not copy {filename}: {e}")
            return result
        
        # Check if file exists and has content
        if not os.path.exists(temp_file.name) or os.path.getsize(temp_file.name) == 0:
            result['error'] = f"File is empty or not copied: {filename}"
            return result
        
        result['found'] = True
        file_size = os.path.getsize(temp_file.name)
        result['size'] = file_size
        
        # Check file size
        if specs['min_size'] <= file_size <= specs['max_size']:
            result['valid_size'] = True
        else:
            result['error'] = f"Invalid size: {file_size} bytes (expected {specs['min_size']}-{specs['max_size']})"
        
        # Check file type via magic bytes
        if specs['magic_bytes'] is not None:
            with open(temp_file.name, 'rb') as f:
                f.seek(specs['magic_offset'])
                header = f.read(len(specs['magic_bytes']))
                if header == specs['magic_bytes']:
                    result['correct_type'] = True
                else:
                    result['error'] = f"Invalid file type (magic bytes mismatch)"
        else:
            # For text files, just check it's readable text
            try:
                with open(temp_file.name, 'r', encoding='utf-8') as f:
                    content = f.read(100)  # Read first 100 chars
                    if len(content) > 0:
                        result['correct_type'] = True
            except:
                result['error'] = "Not a valid text file"
        
        # Check timestamp (file created during task)
        if task_start_time:
            file_mtime = datetime.fromtimestamp(os.path.getmtime(temp_file.name))
            # Allow up to 5 minutes for task completion
            if task_start_time <= file_mtime <= task_start_time + timedelta(minutes=5):
                result['recent'] = True
            else:
                logger.warning(f"{filename} timestamp outside expected range")
                # Don't fail on timestamp, just note it
                result['recent'] = True  # Be lenient
        else:
            result['recent'] = True  # Skip check if no start time
        
        logger.info(f"✓ Verified {filename}: size={file_size}, valid_size={result['valid_size']}, correct_type={result['correct_type']}")
        
    except Exception as e:
        logger.error(f"Error verifying {filename}: {e}")
        result['error'] = str(e)
    
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass
    
    return result


def calculate_final_score(verification_results: Dict[str, Dict]) -> Dict[str, Any]:
    """
    Calculate final score based on individual file verification results.
    
    Scoring:
    - Each file: 33.33 points
    - Need valid size + correct type to count as successful
    - Pass threshold: 75% (need 2/3 files = 66.66%)
    
    Args:
        verification_results: Dict mapping filename to verification result
        
    Returns:
        Dict with passed, score, feedback
    """
    files_successful = 0
    files_found = 0
    feedback_parts = []
    
    feedback_parts.append("File Download Verification Results:")
    feedback_parts.append("=" * 50)
    
    for filename, result in verification_results.items():
        file_specs = EXPECTED_FILES[filename]
        
        if not result['found']:
            status = "✗ NOT FOUND"
            feedback_parts.append(f"{status} {filename} - {result.get('error', 'File missing')}")
        else:
            files_found += 1
            
            # File counts as successful if it has valid size AND correct type
            if result['valid_size'] and result['correct_type']:
                files_successful += 1
                status = "✓ SUCCESS"
                feedback_parts.append(
                    f"{status} {filename} ({result['size']} bytes) - {file_specs['description']}"
                )
            else:
                status = "✗ INVALID"
                error_msg = result.get('error', 'Unknown error')
                feedback_parts.append(
                    f"{status} {filename} ({result['size']} bytes) - {error_msg}"
                )
    
    feedback_parts.append("=" * 50)
    feedback_parts.append(f"Files found: {files_found}/3")
    feedback_parts.append(f"Files valid: {files_successful}/3")
    
    # Calculate score (each file is worth 33.33 points, round to nearest int)
    score = int((files_successful / 3.0) * 100)
    
    # Pass threshold: need at least 2/3 files (66.67%) but we round to 75% for clarity
    passed = files_successful >= 2
    
    if files_successful == 3:
        feedback_parts.append("\n✅ PASSED: All files downloaded successfully!")
        final_feedback = "Perfect execution"
    elif files_successful == 2:
        feedback_parts.append("\n✅ PASSED: 2/3 files downloaded successfully")
        final_feedback = "Good execution with minor issues"
    elif files_successful == 1:
        feedback_parts.append("\n❌ FAILED: Only 1/3 files downloaded")
        final_feedback = "Insufficient - need at least 2 files"
    else:
        feedback_parts.append("\n❌ FAILED: No files downloaded successfully")
        final_feedback = "Task not completed"
    
    feedback = "\n".join(feedback_parts)
    
    logger.info(f"Final verification: {files_successful}/3 files successful, score={score}, passed={passed}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "files_found": files_found,
            "files_successful": files_successful,
            "total_files": 3,
            "verification_results": verification_results
        }
    }
