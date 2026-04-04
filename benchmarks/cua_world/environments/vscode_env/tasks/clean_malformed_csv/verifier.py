#!/usr/bin/env python3
"""
Verifier for Clean Malformed CSV task
"""

import sys
import os
import logging
import tempfile
import csv
import re
from io import StringIO

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content, cleanup_verification_temp

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_csv_cleaning(traj, env_info, task_info):
    """
    Verify that CSV cleaning was performed correctly.

    Checks:
    1. Output file exists and is non-empty
    2. Output is valid CSV (parseable)
    3. All rows have exactly 5 columns
    4. UTF-8 encoding is correct
    5. Reasonable data retention (≥80% of input rows)
    6. Script shows evidence of CSV-aware parsing
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='csv_verify_')

    try:
        # Copy exported files
        output_csv_local = os.path.join(temp_dir, "customer_export_clean.csv")
        script_local = os.path.join(temp_dir, "clean_data.py")
        input_csv_local = os.path.join(temp_dir, "customer_export_broken.csv")

        try:
            copy_from_env("/tmp/customer_export_clean.csv", output_csv_local)
            copy_from_env("/tmp/clean_data.py", script_local)
            copy_from_env("/tmp/customer_export_broken.csv", input_csv_local)
        except Exception as e:
            logger.warning(f"Failed to copy some files: {e}")

        criteria_passed = 0
        feedback_parts = []
        total_criteria = 6

        # Criterion 1: Output file exists and is non-empty
        if os.path.exists(output_csv_local) and os.path.getsize(output_csv_local) > 0:
            criteria_passed += 1
            file_size = os.path.getsize(output_csv_local)
            feedback_parts.append(f"✅ Output file exists ({file_size} bytes)")
        else:
            feedback_parts.append("❌ Output file not found or empty")
            # Can't proceed with further checks
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }

        # Read output CSV content
        try:
            with open(output_csv_local, 'r', encoding='utf-8') as f:
                output_content = f.read()
        except UnicodeDecodeError:
            feedback_parts.append("❌ UTF-8 encoding error in output")
            return {
                "passed": False,
                "score": int((criteria_passed / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }

        # Criterion 2: Valid CSV (parseable)
        valid_csv = False
        rows = []
        try:
            csv_reader = csv.reader(StringIO(output_content))
            rows = list(csv_reader)
            if len(rows) > 0:
                valid_csv = True
                criteria_passed += 1
                feedback_parts.append(f"✅ Valid CSV structure ({len(rows)} rows including header)")
            else:
                feedback_parts.append("❌ CSV is empty")
        except csv.Error as e:
            feedback_parts.append(f"❌ CSV parsing failed: {str(e)[:50]}")
        except Exception as e:
            feedback_parts.append(f"❌ Failed to parse CSV: {str(e)[:50]}")

        if not valid_csv:
            return {
                "passed": False,
                "score": int((criteria_passed / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }

        # Criterion 3: All rows have exactly 5 columns
        consistent_columns = True
        inconsistent_count = 0
        expected_columns = 5

        for i, row in enumerate(rows):
            if len(row) != expected_columns:
                consistent_columns = False
                inconsistent_count += 1

        if consistent_columns and len(rows) > 0:
            criteria_passed += 1
            feedback_parts.append(f"✅ All rows have {expected_columns} columns")
        else:
            feedback_parts.append(f"❌ Column inconsistency: {inconsistent_count} rows don't have {expected_columns} columns")

        # Criterion 4: UTF-8 encoding correct (check for special characters)
        # Look for common UTF-8 characters that should be preserved
        encoding_correct = False
        special_chars = ['é', 'ñ', 'ö', 'ü', 'ø', 'á', 'ó']
        found_special_chars = [char for char in special_chars if char in output_content.lower()]

        # Check for mojibake patterns (common encoding errors)
        mojibake_patterns = ['Ã©', 'Ã±', 'Ã¶', 'â€™', 'Â']
        has_mojibake = any(pattern in output_content for pattern in mojibake_patterns)

        if found_special_chars and not has_mojibake:
            criteria_passed += 1
            encoding_correct = True
            feedback_parts.append(f"✅ UTF-8 encoding correct (found: {', '.join(found_special_chars[:3])})")
        elif not found_special_chars and not has_mojibake:
            # Acceptable if there are no special chars (might have been removed)
            criteria_passed += 1
            encoding_correct = True
            feedback_parts.append("✅ Encoding valid (no special chars or mojibake)")
        else:
            feedback_parts.append("❌ Encoding issues detected (mojibake or corruption)")

        # Criterion 5: Reasonable data retention
        # Count input rows (excluding header)
        input_row_count = 0
        try:
            with open(input_csv_local, 'r', encoding='utf-8', errors='ignore') as f:
                input_row_count = len(f.readlines()) - 1  # Exclude header
        except:
            input_row_count = 50  # Default expected

        output_row_count = len(rows) - 1  # Exclude header
        retention_rate = (output_row_count / input_row_count) * 100 if input_row_count > 0 else 0

        if retention_rate >= 80:
            criteria_passed += 1
            feedback_parts.append(f"✅ Good data retention: {output_row_count}/{input_row_count} rows ({retention_rate:.1f}%)")
        elif retention_rate >= 60:
            # Partial credit for reasonable filtering
            criteria_passed += 0.5
            feedback_parts.append(f"⚠️ Moderate data retention: {output_row_count}/{input_row_count} rows ({retention_rate:.1f}%)")
        else:
            feedback_parts.append(f"❌ Poor data retention: {output_row_count}/{input_row_count} rows ({retention_rate:.1f}%)")

        # Criterion 6: Script shows CSV-aware parsing
        script_quality = False
        if os.path.exists(script_local):
            script_content = read_file_content(script_local)

            # Check for CSV module usage
            uses_csv_module = 'import csv' in script_content or 'from csv import' in script_content
            uses_pandas = 'import pandas' in script_content or 'pd.read_csv' in script_content

            # Check for file I/O
            has_file_io = 'open(' in script_content or 'with open' in script_content

            # Check for UTF-8 encoding specification
            has_encoding = "encoding='utf-8'" in script_content or 'encoding="utf-8"' in script_content

            if (uses_csv_module or uses_pandas) and has_file_io:
                criteria_passed += 1
                script_quality = True
                indicators = []
                if uses_csv_module:
                    indicators.append("csv module")
                if uses_pandas:
                    indicators.append("pandas")
                if has_encoding:
                    indicators.append("UTF-8 encoding")
                feedback_parts.append(f"✅ Script uses proper CSV parsing ({', '.join(indicators)})")
            else:
                # Check if script at least exists and has some content
                if len(script_content.strip()) > 50:
                    feedback_parts.append("⚠️ Script exists but may not use proper CSV parsing")
                else:
                    feedback_parts.append("❌ Script is empty or minimal")
        else:
            feedback_parts.append("❌ Script file not found")

        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75

        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_verification_temp(temp_dir)
