#!/usr/bin/env python3
"""
Verifier for Transform API Response task
Checks that JSON was correctly transformed to CSV with proper structure and data
"""

import sys
import os
import csv
import logging
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import check_file_exists

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_data_transformation(traj, env_info, task_info):
    """
    Verify the data transformation task completed successfully.
    
    Checks:
    1. CSV file exists at expected location
    2. File has correct headers (exact match)
    3. File has exactly 50 data rows (51 total with header)
    4. Sample data validations:
       - First row (ID 1001) has correct transformations
       - Nested fields extracted correctly
       - Null handling works (ID 1002 has null last_login)
       - Empty array handling (ID 1005 has empty tags)
       - Multi-tag array conversion (ID 1004 has 3 tags)
    5. Date format transformation (ISO to YYYY-MM-DD)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available"
        }
    
    temp_dir = tempfile.mkdtemp(prefix='vscode_verify_csv_')
    
    try:
        # Copy the CSV file from container
        csv_container_path = "/tmp/users_export.csv"
        csv_local_path = os.path.join(temp_dir, "users_export.csv")
        
        try:
            copy_from_env(csv_container_path, csv_local_path)
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Failed to copy CSV file: {str(e)}"
            }
        
        # Check file exists and is not empty
        if not os.path.exists(csv_local_path):
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ CSV file not found at /home/ga/workspace/data/users_export.csv"
            }
        
        if os.path.getsize(csv_local_path) == 0:
            return {
                "passed": False,
                "score": 10,
                "feedback": "❌ CSV file exists but is empty"
            }
        
        # Parse CSV
        try:
            with open(csv_local_path, 'r', encoding='utf-8') as f:
                # Read first line to check BOM or encoding issues
                first_char = f.read(1)
                f.seek(0)
                if first_char == '\ufeff':
                    # BOM detected, skip it
                    content = f.read()
                    content = content.lstrip('\ufeff')
                    lines = content.split('\n')
                    reader = csv.DictReader(lines)
                else:
                    reader = csv.DictReader(f)
                
                rows = list(reader)
                headers = reader.fieldnames
        except csv.Error as e:
            return {
                "passed": False,
                "score": 15,
                "feedback": f"❌ CSV parsing error: {str(e)}"
            }
        except Exception as e:
            return {
                "passed": False,
                "score": 15,
                "feedback": f"❌ Error reading CSV: {str(e)}"
            }
        
        feedback_parts = []
        score = 0
        
        # Check 1: Headers (exact match) - 20 points
        expected_headers = ["User ID", "Username", "Email", "Department", "Level", 
                          "Last Login Date", "Status", "Tags"]
        
        if headers == expected_headers:
            score += 20
            feedback_parts.append("✅ Headers correct")
        else:
            feedback_parts.append(f"❌ Headers incorrect. Expected: {expected_headers}, Got: {headers}")
            # This is critical, return early
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts)
            }
        
        # Check 2: Row count (exactly 50 data rows) - 15 points
        if len(rows) == 50:
            score += 15
            feedback_parts.append(f"✅ Correct row count: {len(rows)}")
        else:
            feedback_parts.append(f"❌ Expected 50 data rows, got {len(rows)}")
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts)
            }
        
        # Check 3: Validate first row (ID 1001 - alice_smith) - 25 points
        first_row = rows[0]
        first_row_errors = []
        
        if first_row.get("User ID") != "1001":
            first_row_errors.append(f"User ID should be '1001', got '{first_row.get('User ID')}'")
        
        if first_row.get("Username") != "alice_smith":
            first_row_errors.append(f"Username should be 'alice_smith', got '{first_row.get('Username')}'")
        
        if first_row.get("Email") != "alice@example.com":
            first_row_errors.append(f"Email should be 'alice@example.com', got '{first_row.get('Email')}'")
        
        # Nested field extraction
        if first_row.get("Department") != "Engineering":
            first_row_errors.append(f"Department should be 'Engineering', got '{first_row.get('Department')}'")
        
        if first_row.get("Level") != "Senior":
            first_row_errors.append(f"Level should be 'Senior', got '{first_row.get('Level')}'")
        
        # Date transformation
        if first_row.get("Last Login Date") != "2024-01-15":
            first_row_errors.append(f"Last Login Date should be '2024-01-15', got '{first_row.get('Last Login Date')}'")
        
        if first_row.get("Status") != "active":
            first_row_errors.append(f"Status should be 'active', got '{first_row.get('Status')}'")
        
        # Tags array conversion
        tags = first_row.get("Tags", "")
        if "premium" not in tags.lower() or "verified" not in tags.lower():
            first_row_errors.append(f"Tags should contain 'premium' and 'verified', got '{tags}'")
        
        if first_row_errors:
            feedback_parts.append(f"❌ First row validation failed: {'; '.join(first_row_errors[:3])}")
        else:
            score += 25
            feedback_parts.append("✅ First row data correct")
        
        # Check 4: Null handling (ID 1002 - bob_jones with null last_login) - 15 points
        second_row = rows[1]
        null_handling_ok = False
        
        if second_row.get("User ID") == "1002":
            last_login = second_row.get("Last Login Date", "")
            if last_login in ["N/A", "n/a", "NA", "na"]:
                score += 15
                feedback_parts.append("✅ Null value handling correct")
                null_handling_ok = True
            else:
                feedback_parts.append(f"❌ Null last_login should be 'N/A', got '{last_login}'")
        else:
            feedback_parts.append(f"❌ Second row User ID should be '1002', got '{second_row.get('User ID')}'")
        
        # Check 5: Empty array handling (ID 1005 - evan_thomas with empty tags) - 10 points
        row_1005 = next((r for r in rows if r.get("User ID") == "1005"), None)
        if row_1005:
            tags_1005 = row_1005.get("Tags", None)
            if tags_1005 is not None and tags_1005.strip() == "":
                score += 10
                feedback_parts.append("✅ Empty array handling correct")
            else:
                # Be lenient - empty string is acceptable
                if tags_1005 == "":
                    score += 10
                    feedback_parts.append("✅ Empty array handling correct")
                else:
                    feedback_parts.append(f"⚠️ Empty tags should be empty string, got '{tags_1005}'")
                    score += 5  # Partial credit
        
        # Check 6: Multi-tag array (ID 1004 - diana_prince with 3 tags) - 15 points
        row_1004 = next((r for r in rows if r.get("User ID") == "1004"), None)
        if row_1004:
            tags_1004 = row_1004.get("Tags", "")
            tags_lower = tags_1004.lower()
            if "premium" in tags_lower and "verified" in tags_lower and "beta" in tags_lower:
                score += 15
                feedback_parts.append("✅ Multi-tag array conversion correct")
            else:
                feedback_parts.append(f"❌ Tags for ID 1004 should contain 'premium, verified, beta', got '{tags_1004}'")
        
        # Determine pass/fail
        passed = score >= 90  # Need 90% to pass
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
