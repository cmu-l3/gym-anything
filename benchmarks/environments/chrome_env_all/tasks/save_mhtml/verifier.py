#!/usr/bin/env python3
"""
Verifier for Chrome Save MHTML Task (save_mhtml@1)
Task: Save a complete webpage as a single MHTML file

Verification Strategy:
- Check MHTML file exists in Downloads folder with correct extension
- Validate MHTML format (MIME headers, boundaries, structure)
- Verify file contains embedded resources (not just HTML)
- Ensure reasonable file size
- Check content integrity
"""

import logging
import sys
import os
import re
import tempfile
from pathlib import Path
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path (if available)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available")
    UTILS_AVAILABLE = False
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info):
    """
    Main verification function for save_mhtml@1 task.
    
    Verifies:
    1. MHTML file exists with proper extension
    2. Valid MIME format with proper headers
    3. Contains multipart boundaries
    4. Includes embedded resources (base64 content)
    5. Reasonable file size (>5KB)
    6. Contains expected content from Wikipedia page
    
    Scoring:
    - 100%: All 6 criteria met (perfect MHTML)
    - 75-99%: 5/6 criteria met (minor issues)
    - 50-74%: 4/6 criteria met (functional but flawed)
    - 25-49%: 2-3/6 criteria met (incomplete)
    - 0-24%: 0-1 criteria met (failed)
    
    Pass threshold: 75% (requires 5 out of 6 criteria)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available"
        }
    
    try:
        # Find and copy the MHTML file
        success, mhtml_path, filename, error = find_mhtml_file(copy_from_env)
        
        if not success:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"MHTML file not found: {error}"
            }
        
        logger.info(f"Found MHTML file: {filename}")
        
        # Run verification checks
        criteria_met = 0
        total_criteria = 6
        feedback_parts = []
        
        # Criterion 1: File has correct extension
        ext_ok, ext_feedback = check_file_extension(filename)
        if ext_ok:
            feedback_parts.append(f"✓ {ext_feedback}")
            criteria_met += 1
        else:
            feedback_parts.append(f"✗ {ext_feedback}")
        
        # Criterion 2: File size is reasonable
        size_ok, size_kb, size_feedback = check_file_size(mhtml_path)
        if size_ok:
            feedback_parts.append(f"✓ {size_feedback}")
            criteria_met += 1
        else:
            feedback_parts.append(f"✗ {size_feedback}")
        
        # Criterion 3: Valid MIME format
        mime_ok, mime_feedback = validate_mime_format(mhtml_path)
        if mime_ok:
            feedback_parts.append(f"✓ {mime_feedback}")
            criteria_met += 1
        else:
            feedback_parts.append(f"✗ {mime_feedback}")
        
        # Criterion 4: Contains multipart boundaries
        boundary_ok, boundary_feedback = check_multipart_boundaries(mhtml_path)
        if boundary_ok:
            feedback_parts.append(f"✓ {boundary_feedback}")
            criteria_met += 1
        else:
            feedback_parts.append(f"✗ {boundary_feedback}")
        
        # Criterion 5: Contains embedded resources
        resources_ok, resources_feedback = check_embedded_resources(mhtml_path)
        if resources_ok:
            feedback_parts.append(f"✓ {resources_feedback}")
            criteria_met += 1
        else:
            feedback_parts.append(f"✗ {resources_feedback}")
        
        # Criterion 6: Contains expected content
        content_ok, content_feedback = check_content_validity(mhtml_path)
        if content_ok:
            feedback_parts.append(f"✓ {content_feedback}")
            criteria_met += 1
        else:
            feedback_parts.append(f"✗ {content_feedback}")
        
        # Calculate score
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75
        
        # Build final feedback
        feedback = "\n".join(feedback_parts)
        feedback += f"\n\n{'='*50}"
        feedback += f"\nCriteria met: {criteria_met}/{total_criteria}"
        feedback += f"\nFinal score: {score}%"
        feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
        
        # Clean up
        cleanup_mhtml_temp(mhtml_path)
        cleanup_verification_temp()
        
        logger.info(f"Verification complete: passed={passed}, score={score}")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "details": {
                "filename": filename,
                "size_kb": size_kb if size_ok else 0,
                "criteria_met": criteria_met,
                "has_mime_headers": mime_ok,
                "has_resources": resources_ok,
                "has_content": content_ok
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def find_mhtml_file(copy_from_env):
    """
    Find and copy MHTML file from container.
    
    Returns:
        tuple: (success, local_path, filename, error_message)
    """
    try:
        # First, try to get the filename that was found
        temp_filename = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env("/tmp/mhtml_filename.txt", temp_filename.name)
            with open(temp_filename.name, 'r') as f:
                found_name = f.read().strip()
            os.unlink(temp_filename.name)
            
            if found_name == "none" or not found_name:
                return False, "", "", "No MHTML file was found in Downloads folder"
        except Exception as e:
            logger.warning(f"Could not read mhtml_filename.txt: {e}")
            # Try to find any MHTML file
            found_name = None
        
        # Try to copy the MHTML file
        temp_mhtml = tempfile.NamedTemporaryFile(delete=False, suffix='.mhtml')
        temp_mhtml.close()
        
        # Try multiple possible locations
        possible_paths = []
        
        if found_name:
            possible_paths.extend([
                f"/tmp/mhtml_verification/{found_name}",
                f"/tmp/{found_name}",
                f"/home/ga/Downloads/{found_name}",
            ])
        
        # Also try common default names
        possible_paths.extend([
            "/home/ga/Downloads/Web_archiving.mhtml",
            "/home/ga/Downloads/Web archiving.mhtml",
            "/home/ga/Downloads/Wikipedia.mhtml",
        ])
        
        for container_path in possible_paths:
            try:
                logger.info(f"Trying to copy from: {container_path}")
                copy_from_env(container_path, temp_mhtml.name)
                
                # Check if file has content
                if Path(temp_mhtml.name).stat().st_size > 0:
                    logger.info(f"✓ Successfully copied MHTML from: {container_path}")
                    actual_filename = found_name if found_name else os.path.basename(container_path)
                    return True, temp_mhtml.name, actual_filename, ""
            except Exception as e:
                logger.debug(f"Could not copy from {container_path}: {e}")
                continue
        
        # If we get here, none of the paths worked
        os.unlink(temp_mhtml.name)
        return False, "", "", "MHTML file could not be copied from container"
        
    except Exception as e:
        logger.error(f"Error finding MHTML: {e}", exc_info=True)
        return False, "", "", f"Error finding MHTML: {str(e)}"


def check_file_extension(filename):
    """Check if file has proper MHTML extension."""
    if not filename:
        return False, "No filename provided"
    
    filename_lower = filename.lower()
    if filename_lower.endswith('.mhtml') or filename_lower.endswith('.mht'):
        return True, f"Correct file extension: {filename}"
    else:
        return False, f"Incorrect extension: {filename} (expected .mhtml or .mht)"


def check_file_size(filepath):
    """Check if file has reasonable size for MHTML."""
    try:
        size_bytes = Path(filepath).stat().st_size
        size_kb = size_bytes / 1024
        
        if size_bytes < 1024:  # Less than 1KB
            return False, size_kb, f"File too small ({size_bytes} bytes)"
        elif size_bytes < 5120:  # Less than 5KB
            return False, size_kb, f"File suspiciously small ({size_kb:.1f} KB)"
        else:
            return True, size_kb, f"File size OK ({size_kb:.1f} KB)"
            
    except Exception as e:
        return False, 0, f"Could not check file size: {e}"


def validate_mime_format(filepath):
    """Validate MHTML has proper MIME headers."""
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            # Read first 2KB to check headers
            header = f.read(2048)
        
        # Must contain MIME-Version header
        if 'MIME-Version:' not in header and 'MIME-Version: 1.0' not in header:
            return False, "Missing MIME-Version header"
        
        # Must contain multipart/related content type
        if 'multipart/related' not in header:
            return False, "Missing multipart/related Content-Type"
        
        # Should contain From header (Chrome signature)
        if 'From:' not in header:
            return False, "Missing From header (not Chrome MHTML format)"
        
        return True, "Valid MIME format headers detected"
        
    except Exception as e:
        logger.error(f"Error validating MIME format: {e}")
        return False, f"Could not validate MIME format: {e}"


def check_multipart_boundaries(filepath):
    """Check for proper MIME multipart boundaries."""
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read(8192)  # Read first 8KB
        
        # Look for boundary declaration
        boundary_match = re.search(r'boundary="?([^"\s]+)"?', content, re.IGNORECASE)
        if not boundary_match:
            return False, "No boundary declaration found"
        
        boundary = boundary_match.group(1)
        
        # Check that boundary is actually used in content
        boundary_marker = f"--{boundary}"
        if boundary_marker not in content:
            return False, f"Boundary '{boundary}' declared but not found in content"
        
        # Count boundary occurrences (should have multiple parts)
        boundary_count = content.count(boundary_marker)
        if boundary_count < 2:
            return False, f"Only {boundary_count} boundary marker(s) found (need at least 2)"
        
        return True, f"Valid multipart boundaries found ({boundary_count} parts)"
        
    except Exception as e:
        logger.error(f"Error checking boundaries: {e}")
        return False, f"Could not check boundaries: {e}"


def check_embedded_resources(filepath):
    """Check if MHTML contains embedded resources."""
    try:
        with open(filepath, 'rb') as f:
            content = f.read()
        
        # Check for base64-encoded content (images, CSS, etc.)
        if b'Content-Transfer-Encoding: base64' in content:
            # Count how many base64 sections
            base64_count = content.count(b'Content-Transfer-Encoding: base64')
            return True, f"Embedded resources detected ({base64_count} base64-encoded parts)"
        
        # Check for quoted-printable encoded resources
        if b'Content-Transfer-Encoding: quoted-printable' in content:
            return True, "Embedded resources detected (quoted-printable)"
        
        # Check for inline data URIs
        if b'data:image' in content:
            return True, "Embedded resources detected (data URIs)"
        
        # Check for multiple Content-Type declarations (HTML + resources)
        content_type_count = content.count(b'Content-Type:')
        if content_type_count >= 3:  # HTML + at least 2 resources
            return True, f"Multiple content parts detected ({content_type_count})"
        
        return False, "No embedded resources found (may be HTML-only)"
        
    except Exception as e:
        logger.error(f"Error checking resources: {e}")
        return False, f"Could not check resources: {e}"


def check_content_validity(filepath):
    """Check if MHTML contains expected content from the Wikipedia page."""
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
        
        content_lower = content.lower()
        
        # Expected keywords from Wikipedia "Web archiving" article
        expected_keywords = [
            'wikipedia',
            'archive',
            'archiving',
            'web',
            'internet',
        ]
        
        # Check for HTML content
        if '<html' not in content_lower and '<!doctype' not in content_lower:
            return False, "No HTML content detected"
        
        # Count matching keywords
        matches = sum(1 for kw in expected_keywords if kw in content_lower)
        
        # Need at least 60% of keywords
        required_matches = max(2, int(len(expected_keywords) * 0.6))
        
        if matches >= required_matches:
            return True, f"Valid content detected ({matches}/{len(expected_keywords)} keywords found)"
        else:
            return False, f"Insufficient content ({matches}/{len(expected_keywords)} keywords, need {required_matches})"
        
    except Exception as e:
        logger.error(f"Error checking content: {e}")
        return False, f"Could not check content: {e}"


def cleanup_mhtml_temp(filepath):
    """Clean up temporary MHTML file."""
    try:
        if filepath and os.path.exists(filepath):
            os.unlink(filepath)
    except Exception as e:
        logger.warning(f"Could not clean up temp file: {e}")
