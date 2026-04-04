#!/usr/bin/env python3
"""
Verifier for Export Data task in MySQL Workbench

Verifies that Japanese cities data was exported from the World database:
1. Output file exists with exported data
2. Output contains correct number of rows (248 Japanese cities)
3. Output contains known Japanese cities
4. Output validates against actual database (anti-gaming)
5. Correct column structure
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Known Japanese cities that should appear in results
KNOWN_JAPAN_CITIES = [
    "Tokyo",
    "Jokohama",  # Yokohama in the database
    "Yokohama",
    "Osaka",
    "Nagoya",
    "Sapporo",
    "Kobe",
    "Fukuoka",
    "Kawasaki",
    "Hiroshima",
    "Sendai",
    "Chiba"
]


def verify_export_data(traj, env_info, task_info):
    """
    Verify that Japanese cities data was exported successfully.

    Criteria:
    1. Output file exists at expected path (REQUIRED)
    2. Output has correct row count (~248) (REQUIRED)
    3. Output contains known Japanese cities (REQUIRED)
    4. Database validation of content (anti-gaming)
    5. Correct column structure
    6. VLM verification of results (if available)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get VLM function for visual verification
    query_vlm = env_info.get('query_vlm')

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_city_count = metadata.get('expected_city_count', 248)
    expected_output_file = metadata.get('expected_output_file', '/home/ga/Documents/exports/japan_cities.csv')

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/export_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        # Initialize scoring
        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        critical_failures = []

        # Extract result data
        workbench_running = result.get('workbench_running', False)
        export_successful = result.get('export_successful', False)
        output_file_exists = result.get('output_file_exists', False)
        output_row_count = result.get('output_row_count', 0)
        correct_city_count = result.get('correct_city_count', False)
        known_cities_matched = result.get('known_cities_matched', 0)
        cities_found = result.get('cities_found', '')
        db_validated_count = result.get('db_validated_count', 0)
        actual_db_count = result.get('actual_db_count', 0)
        column_count = result.get('column_count', 0)
        has_correct_columns = result.get('has_correct_columns', False)

        logger.info(f"Result: output_exists={output_file_exists}, rows={output_row_count}, "
                   f"cities_matched={known_cities_matched}, db_validated={db_validated_count}")

        # CRITICAL CHECK 1: Output file must exist
        if not output_file_exists:
            critical_failures.append(f"Output file not found at {expected_output_file}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"FAILED: Data not exported. Must export results to: {expected_output_file}",
                "subscores": {
                    "output_file_exists": False,
                    "correct_row_count": False,
                    "cities_validated": False,
                    "db_validated": False,
                    "correct_columns": False,
                    "vlm_verified": False
                }
            }

        # Criterion 1: Output file exists
        criteria_passed += 1
        feedback_parts.append("Output file exists")

        # CRITICAL CHECK 2: Correct row count
        # Allow tolerance of +/- 15 rows
        if correct_city_count or (abs(output_row_count - expected_city_count) <= 15):
            criteria_passed += 1
            feedback_parts.append(f"Row count correct: {output_row_count} cities")
        elif output_row_count > 0:
            if output_row_count > expected_city_count:
                criteria_passed += 0.3
                feedback_parts.append(f"TOO MANY ROWS: {output_row_count} (expected ~{expected_city_count})")
            else:
                criteria_passed += 0.3
                feedback_parts.append(f"TOO FEW ROWS: {output_row_count} (expected ~{expected_city_count})")
        else:
            critical_failures.append("Output file is empty")
            feedback_parts.append("NO DATA: Output file has no rows")

        # CRITICAL CHECK 3: Known cities validated
        min_cities_required = 3
        if known_cities_matched >= min_cities_required:
            criteria_passed += 1
            feedback_parts.append(f"City content validated: {known_cities_matched} known cities found")
        elif known_cities_matched > 0:
            criteria_passed += 0.5
            feedback_parts.append(f"PARTIAL MATCH: Only {known_cities_matched} known cities (need {min_cities_required})")
        else:
            critical_failures.append("No known Japanese cities found in output")
            feedback_parts.append("INVALID CONTENT: No Japanese cities detected")

        # Criterion 4: Database validation (anti-gaming)
        min_db_validated = 10
        if db_validated_count >= min_db_validated:
            criteria_passed += 1
            feedback_parts.append(f"Database validated: {db_validated_count} entries verified")
        elif db_validated_count > 0:
            criteria_passed += 0.5
            feedback_parts.append(f"PARTIAL DB VALIDATION: {db_validated_count}/{min_db_validated} entries")
        else:
            feedback_parts.append("Database validation failed")

        # Criterion 5: Correct column structure
        if has_correct_columns:
            criteria_passed += 1
            feedback_parts.append(f"Column structure correct: {column_count} columns")
        elif column_count > 0:
            criteria_passed += 0.5
            feedback_parts.append(f"Columns present but count may be off: {column_count}")
        else:
            feedback_parts.append("Column structure not verified")

        # Criterion 6: VLM visual verification if available
        vlm_verified = False
        if query_vlm:
            try:
                temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
                try:
                    copy_from_env("/tmp/task_end_screenshot.png", temp_screenshot.name)

                    vlm_prompt = """Analyze this screenshot of MySQL Workbench.

                    Questions:
                    1. Is there a SQL Editor/Query tab visible?
                    2. Are there query results visible in a data grid/table?
                    3. Does the visible data appear to show city names and population data?
                    4. Are Japanese city names visible (like Tokyo, Osaka, Nagoya)?

                    Respond with "VERIFIED" if you can see query results with city data,
                    or "NOT VERIFIED" if no results are visible.
                    """

                    vlm_result = query_vlm(
                        image=temp_screenshot.name,
                        prompt=vlm_prompt
                    )

                    if vlm_result:
                        logger.info(f"VLM result: {vlm_result}")
                        vlm_text = str(vlm_result).upper()
                        if 'VERIFIED' in vlm_text and 'NOT VERIFIED' not in vlm_text:
                            vlm_verified = True
                finally:
                    os.unlink(temp_screenshot.name)
            except Exception as e:
                logger.warning(f"VLM verification failed: {e}")

        if vlm_verified:
            criteria_passed += 1
            feedback_parts.append("VLM: Query results visible")
        else:
            # Partial credit if output file validates
            if output_file_exists and correct_city_count and db_validated_count >= min_db_validated:
                criteria_passed += 0.5
                feedback_parts.append("VLM: Not verified (but output validates)")
            else:
                feedback_parts.append("VLM: Could not verify results visible")

        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)

        # STRICT PASS REQUIREMENTS:
        # - Output file must exist
        # - Correct city count (~248)
        # - At least 3 known Japanese cities matched
        # - Database validation passed (anti-gaming)
        # - Score >= 75%
        passed = (
            output_file_exists and
            (correct_city_count or abs(output_row_count - expected_city_count) <= 15) and
            known_cities_matched >= min_cities_required and
            db_validated_count >= min_db_validated and
            score >= 75
        )

        if critical_failures:
            feedback_parts.insert(0, "CRITICAL: " + "; ".join(critical_failures))

        if cities_found:
            feedback_parts.append(f"Cities found: {cities_found[:100]}")

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": {
                "output_file_exists": output_file_exists,
                "correct_row_count": correct_city_count or abs(output_row_count - expected_city_count) <= 15,
                "cities_validated": known_cities_matched >= min_cities_required,
                "db_validated": db_validated_count >= min_db_validated,
                "correct_columns": has_correct_columns,
                "vlm_verified": vlm_verified
            }
        }

    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - export_result.sh may not have run"
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid JSON in result file: {str(e)}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
