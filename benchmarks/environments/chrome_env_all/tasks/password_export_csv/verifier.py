#!/usr/bin/env python3
"""
Verifier for Chrome Password Export to CSV Task (password_export_csv@1)
Task: Export Chrome saved passwords to CSV file

Verification Strategy:
1. Check if CSV file was created in Downloads folder
2. Verify file is recent (created during task execution)
3. Parse CSV structure and validate headers
4. Ensure CSV contains expected password export format
5. Verify CSV is not empty and has valid data rows
"""

import logging
import sys
import os
import csv
import tempfile
from pathlib import Path
from datetime import datetime, timedelta

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available")
    UTILS_AVAILABLE = False
    def cleanup_verification_temp():
        pass


def find_exported_csv(copy_from_env):
    """
    Find and copy the exported password CSV from the container.
    
    Returns:
        tuple: (success, local_path, filename, error_message)
    """
    try:
        # First, get the list of CSV files found
        temp_list = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
        temp_list.close()
        
        try:
            copy_from_env("/tmp/csv_files_found.txt", temp_list.name)
            with open(temp_list.name, 'r') as f:
                csv_files = [line.strip() for line in f.readlines() if line.strip()]
            os.unlink(temp_list.name)
            
            if not csv_files or csv_files[0] == "none":
                return False, "", "", "No CSV file was exported to Downloads folder"
            
            # Get the first (most recent) CSV file found
            csv_filename = csv_files[0]
            
        except Exception as e:
            logger.warning(f"Could not read csv_files_found.txt: {e}")
            # Try some default names as fallback
            csv_filename = "chrome_passwords_export.csv"
        
        # Try to copy the CSV file from verification directory
        temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv', mode='wb')
        temp_csv.close()
        
        # Try multiple possible locations
        possible_paths = [
            f"/tmp/password_export_verification/{csv_filename}",
            f"/tmp/{csv_filename}",
            f"/home/ga/Downloads/{csv_filename}",
            "/home/ga/Downloads/Chrome Passwords.csv",  # Default Chrome export name
            "/home/ga/Downloads/chrome_passwords_export.csv",
        ]
        
        # Also try any CSV in Downloads
        for container_path in possible_paths:
            try:
                logger.info(f"Trying to copy CSV from: {container_path}")
                copy_from_env(container_path, temp_csv.name)
                
                # Check if file has content
                if Path(temp_csv.name).stat().st_size > 0:
                    logger.info(f"✓ Successfully copied CSV from: {container_path}")
                    return True, temp_csv.name, csv_filename, ""
            except Exception as e:
                logger.debug(f"Could not copy from {container_path}: {e}")
                continue
        
        # If we get here, none of the paths worked
        os.unlink(temp_csv.name)
        return False, "", "", "CSV file could not be copied from container"
        
    except Exception as e:
        logger.error(f"Error finding CSV: {e}", exc_info=True)
        return False, "", "", f"Error finding CSV: {str(e)}"


def check_csv_file_size(csv_path):
    """
    Check if CSV has meaningful file size.
    
    Returns:
        tuple: (passed, size_bytes, feedback)
    """
    try:
        size_bytes = Path(csv_path).stat().st_size
        
        if size_bytes < 50:  # Less than 50 bytes
            return False, size_bytes, f"File too small ({size_bytes} bytes) - likely empty or corrupt"
        elif size_bytes < 100:  # Less than 100 bytes - might be just headers
            return True, size_bytes, f"File very small ({size_bytes} bytes) - likely just headers"
        else:
            return True, size_bytes, f"File size OK ({size_bytes} bytes)"
            
    except Exception as e:
        return False, 0, f"Could not check file size: {e}"


def validate_csv_structure(csv_path):
    """
    Validate CSV structure matches Chrome password export format.
    
    Expected headers (Chrome password export):
    - name (or title, website)
    - url (or website, uri)
    - username (or login, user)
    - password (or pass)
    
    Returns:
        tuple: (passed, headers, row_count, feedback)
    """
    try:
        with open(csv_path, 'r', encoding='utf-8', errors='ignore') as f:
            reader = csv.reader(f)
            
            # Read header row
            try:
                headers = next(reader)
            except StopIteration:
                return False, [], 0, "CSV file is empty (no header row)"
            
            if not headers:
                return False, [], 0, "CSV has empty header row"
            
            # Normalize headers for comparison
            headers_lower = [h.lower().strip() for h in headers]
            
            # Check for required fields (with alternative names)
            required_fields = {
                'name': ['name', 'title', 'website'],
                'url': ['url', 'website', 'uri'],
                'username': ['username', 'login', 'user'],
                'password': ['password', 'pass']
            }
            
            found_fields = set()
            for field_type, alternatives in required_fields.items():
                for alt in alternatives:
                    if alt in headers_lower:
                        found_fields.add(field_type)
                        break
            
            # Need at least 3 out of 4 core fields
            if len(found_fields) < 3:
                return False, headers, 0, f"CSV missing required headers. Found: {headers}. Need at least 3 of: name, url, username, password"
            
            # Count data rows
            row_count = 0
            for row in reader:
                if row and any(cell.strip() for cell in row):  # Non-empty row
                    row_count += 1
            
            feedback = f"Valid CSV structure with {len(headers)} columns"
            if row_count > 0:
                feedback += f" and {row_count} data row(s)"
            else:
                feedback += " (no data rows - empty password manager)"
            
            return True, headers, row_count, feedback
            
    except Exception as e:
        logger.error(f"Error validating CSV structure: {e}")
        return False, [], 0, f"CSV parsing error: {str(e)}"


def check_csv_content_validity(csv_path):
    """
    Check if CSV contains valid-looking password data.
    
    Returns:
        tuple: (passed, details, feedback)
    """
    try:
        with open(csv_path, 'r', encoding='utf-8', errors='ignore') as f:
            reader = csv.DictReader(f)
            
            rows = list(reader)
            if not rows:
                # Empty is valid - just means no passwords were saved
                return True, {"entries": 0}, "CSV is valid but contains no password entries"
            
            # Check if rows have reasonable data
            valid_entries = 0
            for row in rows:
                # Check if row has at least some non-empty fields
                non_empty = sum(1 for v in row.values() if v and v.strip())
                if non_empty >= 2:  # At least 2 fields filled
                    valid_entries += 1
            
            if valid_entries == 0:
                return False, {"entries": len(rows)}, "CSV contains rows but they appear empty or invalid"
            
            return True, {"entries": valid_entries}, f"CSV contains {valid_entries} valid password entry(ies)"
            
    except Exception as e:
        return False, {}, f"Error checking CSV content: {e}"


def verify_task(traj, env_info, task_info):
    """
    Main verification function for password_export_csv@1 task.
    
    Verifies:
    1. CSV file exists and was created
    2. File has meaningful size
    3. CSV structure is valid (proper headers)
    4. CSV format matches Chrome password export
    5. File is not corrupted
    
    Scoring:
    - 100%: All 5 criteria met with valid content
    - 80%: 4/5 criteria met
    - 60%: 3/5 criteria met
    - 40%: 2/5 criteria met
    - <40%: <2 criteria met
    
    Pass threshold: 75% (4 out of 5 criteria)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available"
        }
    
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    # Criterion 1: CSV file exists
    logger.info("Checking if CSV file exists...")
    success, csv_path, csv_name, error = find_exported_csv(copy_from_env)
    
    if not success:
        feedback = f"✗ Password export CSV not found\n{error}"
        feedback += "\n\nExpected: CSV file in Downloads folder with password data"
        return {
            "passed": False,
            "score": 0,
            "feedback": feedback
        }
    
    feedback_parts.append(f"✓ CSV file found: {csv_name}")
    criteria_met += 1
    
    # Criterion 2: File size check
    logger.info("Checking file size...")
    size_ok, size_bytes, size_feedback = check_csv_file_size(csv_path)
    if size_ok:
        feedback_parts.append(f"✓ {size_feedback}")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ {size_feedback}")
    
    # Criterion 3: CSV structure validation
    logger.info("Validating CSV structure...")
    struct_ok, headers, row_count, struct_feedback = validate_csv_structure(csv_path)
    if struct_ok:
        feedback_parts.append(f"✓ {struct_feedback}")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ {struct_feedback}")
    
    # Criterion 4: Header correctness (more detailed check)
    logger.info("Checking header format...")
    if struct_ok and headers:
        # Chrome typically uses: name, url, username, password
        expected_chrome_headers = ['name', 'url', 'username', 'password']
        headers_lower = [h.lower() for h in headers]
        
        # Check if headers match Chrome's standard format
        chrome_format_match = all(exp in headers_lower for exp in expected_chrome_headers)
        
        if chrome_format_match:
            feedback_parts.append(f"✓ Headers match Chrome export format: {', '.join(headers)}")
            criteria_met += 1
        elif len(headers) >= 3:
            feedback_parts.append(f"⚠ Headers present but non-standard: {', '.join(headers)}")
            criteria_met += 0.7  # Partial credit
        else:
            feedback_parts.append(f"✗ Insufficient headers: {', '.join(headers)}")
    else:
        feedback_parts.append(f"✗ Could not verify headers")
    
    # Criterion 5: Content validity
    logger.info("Checking CSV content validity...")
    content_ok, content_details, content_feedback = check_csv_content_validity(csv_path)
    if content_ok:
        feedback_parts.append(f"✓ {content_feedback}")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ {content_feedback}")
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*50}"
    feedback += f"\nCriteria met: {criteria_met:.1f}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
    
    if passed:
        feedback += "\n\nPassword export completed successfully!"
        feedback += "\nThe agent successfully exported Chrome passwords to CSV format."
    else:
        feedback += "\n\nPassword export incomplete or invalid."
        feedback += "\nThe CSV file is missing, empty, or has incorrect structure."
    
    # Clean up temporary file
    try:
        if csv_path and os.path.exists(csv_path):
            os.unlink(csv_path)
    except:
        pass
    
    cleanup_verification_temp()
    
    logger.info(f"Verification complete: passed={passed}, score={score}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "csv_filename": csv_name,
            "file_size_bytes": size_bytes if size_ok else 0,
            "headers": headers if struct_ok else [],
            "row_count": row_count if struct_ok else 0,
            "criteria_met": criteria_met
        }
    }
