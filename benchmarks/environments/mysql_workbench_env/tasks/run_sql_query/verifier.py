#!/usr/bin/env python3
"""
Verifier for Run SQL Query task in MySQL Workbench

Verifies actual query execution by checking:
1. Output file exists with query results
2. Output contains correct number of rows (336 films with rental_rate > 2.99)
3. Output contains known film titles
4. Output validates against actual database (anti-gaming)
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Known film titles that should appear in results (rental_rate > 2.99 means rental_rate = 4.99 in Sakila)
KNOWN_EXPENSIVE_FILMS = [
    "ACE GOLDFINGER",
    "AIRPLANE SIERRA",
    "AIRPORT POLLOCK",
    "ALADDIN CALENDAR",
    "ALI FOREVER",
    "AMELIE HELLFIGHTERS",
    "AMERICAN CIRCUS",
    "ANTHEM LUKE",
    "APACHE DIVINE",
    "APOCALYPSE FLAMINGOS",
    "ATTACKS HATE",
    "ATTRACTION NEWTON"
]


def verify_run_sql_query(traj, env_info, task_info):
    """
    Verify that a SQL query was executed and results were saved.

    Criteria:
    1. Output file exists at expected path (REQUIRED)
    2. Output has correct row count (~336) (REQUIRED)
    3. Output contains known film titles (REQUIRED)
    4. Database validation of content (anti-gaming)
    5. SQL query file found (bonus)
    6. VLM verification of results (if available)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get VLM function for visual verification
    query_vlm = env_info.get('query_vlm')

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_film_count = metadata.get('expected_film_count', 336)
    expected_output_file = metadata.get('expected_output_file', '/home/ga/Documents/exports/expensive_films.csv')

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/query_result.json", temp_result.name)
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
        query_executed = result.get('query_executed', False)
        output_file_exists = result.get('output_file_exists', False)
        output_row_count = result.get('output_row_count', 0)
        correct_film_count = result.get('correct_film_count', False)
        known_films_matched = result.get('known_films_matched', 0)
        films_found = result.get('films_found', '')
        db_validated_count = result.get('db_validated_count', 0)
        actual_db_count = result.get('actual_db_count', 0)
        sql_file_found = result.get('sql_file_found', False)

        logger.info(f"Result: output_exists={output_file_exists}, rows={output_row_count}, "
                   f"films_matched={known_films_matched}, db_validated={db_validated_count}")

        # CRITICAL CHECK 1: Output file must exist
        if not output_file_exists:
            critical_failures.append(f"Output file not found at {expected_output_file}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"FAILED: Query results not saved. Must export results to: {expected_output_file}",
                "subscores": {
                    "output_file_exists": False,
                    "correct_row_count": False,
                    "films_validated": False,
                    "db_validated": False,
                    "query_executed": False,
                    "vlm_verified": False
                }
            }

        # Criterion 1: Output file exists
        criteria_passed += 1
        feedback_parts.append("Output file exists")

        # CRITICAL CHECK 2: Correct row count
        # Allow tolerance of +/- 10 rows
        if correct_film_count or (abs(output_row_count - expected_film_count) <= 10):
            criteria_passed += 1
            feedback_parts.append(f"Row count correct: {output_row_count} films")
        elif output_row_count > 0:
            # Some rows but wrong count
            if output_row_count > expected_film_count:
                criteria_passed += 0.3
                feedback_parts.append(f"TOO MANY ROWS: {output_row_count} (expected ~{expected_film_count})")
            else:
                criteria_passed += 0.3
                feedback_parts.append(f"TOO FEW ROWS: {output_row_count} (expected ~{expected_film_count})")
        else:
            critical_failures.append("Output file is empty")
            feedback_parts.append("NO DATA: Output file has no rows")

        # CRITICAL CHECK 3: Known films validated
        min_films_required = 3
        if known_films_matched >= min_films_required:
            criteria_passed += 1
            feedback_parts.append(f"Film content validated: {known_films_matched} known films found")
        elif known_films_matched > 0:
            criteria_passed += 0.5
            feedback_parts.append(f"PARTIAL MATCH: Only {known_films_matched} known films (need {min_films_required})")
        else:
            critical_failures.append("No known Sakila films found in output")
            feedback_parts.append("INVALID CONTENT: No Sakila films detected")

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

        # Criterion 5: Query execution verified
        if query_executed:
            criteria_passed += 1
            feedback_parts.append("Query execution verified")
        else:
            feedback_parts.append("Query execution not fully verified")

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
                    3. Does the visible data appear to show film titles and prices/rates?
                    4. Does the result appear to have many rows of data?

                    Respond with "VERIFIED" if you can see query results with film data,
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
            if output_file_exists and correct_film_count and db_validated_count >= min_db_validated:
                criteria_passed += 0.5
                feedback_parts.append("VLM: Not verified (but output validates)")
            else:
                feedback_parts.append("VLM: Could not verify results visible")

        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)

        # STRICT PASS REQUIREMENTS:
        # - Output file must exist
        # - Correct film count (~336)
        # - At least 3 known films matched
        # - Database validation passed (anti-gaming)
        # - Score >= 75%
        passed = (
            output_file_exists and
            (correct_film_count or abs(output_row_count - expected_film_count) <= 10) and
            known_films_matched >= min_films_required and
            db_validated_count >= min_db_validated and
            score >= 75
        )

        if critical_failures:
            feedback_parts.insert(0, "CRITICAL: " + "; ".join(critical_failures))

        if films_found:
            feedback_parts.append(f"Films found: {films_found[:100]}")

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": {
                "output_file_exists": output_file_exists,
                "correct_row_count": correct_film_count or abs(output_row_count - expected_film_count) <= 10,
                "films_validated": known_films_matched >= min_films_required,
                "db_validated": db_validated_count >= min_db_validated,
                "query_executed": query_executed,
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
