#!/usr/bin/env python3
"""
Verifier for Run SQL Query task in DBeaver

Verifies actual query execution by checking:
1. Output file exists with query results
2. Output contains correct number of rows (18 AC/DC tracks)
3. Output contains known AC/DC track names
4. Does NOT require specific SQL syntax - any valid approach is accepted
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Known AC/DC track names for validation
KNOWN_ACDC_TRACKS = [
    "For Those About To Rock",
    "Put The Finger On You",
    "Let There Be Rock",
    "Hell Ain't A Bad Place To Be",
    "Whole Lotta Rosie",
    "Dog Eat Dog",
    "Problem Child",
    "Overdose",
    "Inject The Venom",
    "Snowballed",
    "Evil Walks",
    "C.O.D.",
    "Breaking The Rules",
    "Night Of The Long Knives",
    "Spellbound",
    "Go Down",
    "Bad Boy Boogie",
    "Lets Get It Up"
]


def verify_run_sql_query(traj, env_info, task_info):
    """
    Verify that a SQL query was executed and results were saved.

    Criteria:
    1. Output file exists at expected path (REQUIRED)
    2. Output has correct row count (~18) (REQUIRED)
    3. Output contains known AC/DC track names (REQUIRED)
    4. SQL query file found (bonus, not required)
    5. VLM verification of results (if available)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get VLM function for visual verification
    query_vlm = env_info.get('query_vlm')

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_track_count = metadata.get('expected_track_count', 18)
    expected_output_file = metadata.get('expected_output_file', '/home/ga/Documents/exports/acdc_tracks.csv')

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
        total_criteria = 5
        feedback_parts = []
        critical_failures = []

        # Extract result data
        dbeaver_running = result.get('dbeaver_running', False)
        query_executed = result.get('query_executed', False)
        output_file_exists = result.get('output_file_exists', False)
        output_row_count = result.get('output_row_count', 0)
        correct_track_count = result.get('correct_track_count', False)
        known_tracks_matched = result.get('known_tracks_matched', 0)
        tracks_found = result.get('tracks_found', '')
        sql_file_found = result.get('sql_file_found', False)

        logger.info(f"Result: output_exists={output_file_exists}, rows={output_row_count}, "
                   f"tracks_matched={known_tracks_matched}, query_executed={query_executed}")

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
                    "tracks_validated": False,
                    "query_executed": False,
                    "vlm_verified": False
                }
            }

        # Criterion 1: Output file exists
        criteria_passed += 1
        feedback_parts.append("Output file exists")

        # CRITICAL CHECK 2: Correct row count
        if correct_track_count:
            criteria_passed += 1
            feedback_parts.append(f"Row count correct: {output_row_count} tracks")
        elif output_row_count > 0:
            # Some rows but wrong count
            criteria_passed += 0.3
            feedback_parts.append(f"WRONG COUNT: {output_row_count} rows (expected ~{expected_track_count})")
        else:
            critical_failures.append("Output file is empty")
            feedback_parts.append("NO DATA: Output file has no rows")

        # CRITICAL CHECK 3: Known tracks validated
        # Require at least 3 known tracks to be present
        min_tracks_required = 3
        if known_tracks_matched >= min_tracks_required:
            criteria_passed += 1
            feedback_parts.append(f"Track content validated: {known_tracks_matched} known AC/DC tracks found")
        elif known_tracks_matched > 0:
            criteria_passed += 0.5
            feedback_parts.append(f"PARTIAL MATCH: Only {known_tracks_matched} known tracks (need {min_tracks_required})")
        else:
            critical_failures.append("No known AC/DC tracks found in output")
            feedback_parts.append("INVALID CONTENT: No AC/DC tracks detected")

        # Criterion 4: Query execution verified
        if query_executed:
            criteria_passed += 1
            feedback_parts.append("Query execution verified")
        else:
            feedback_parts.append("Query execution not fully verified")

        # Criterion 5: VLM visual verification if available
        vlm_verified = False
        if query_vlm:
            try:
                temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
                try:
                    copy_from_env("/tmp/task_end_screenshot.png", temp_screenshot.name)

                    vlm_prompt = """Analyze this screenshot of DBeaver database tool.

                    Questions:
                    1. Is there a SQL Editor panel visible with a query?
                    2. Are there query results visible in a data grid/table?
                    3. Does the visible data appear to show music track names?

                    Respond with "VERIFIED" if you can see query results with data,
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
            # Partial credit if output file is valid
            if output_file_exists and correct_track_count and known_tracks_matched >= min_tracks_required:
                criteria_passed += 0.5
                feedback_parts.append("VLM: Not verified (but output file validates)")
            else:
                feedback_parts.append("VLM: Could not verify results visible")

        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)

        # STRICT PASS REQUIREMENTS:
        # - Output file must exist
        # - Correct track count (~18)
        # - At least 3 known AC/DC tracks matched
        # - Score >= 80%
        passed = (
            output_file_exists and
            correct_track_count and
            known_tracks_matched >= min_tracks_required and
            score >= 80
        )

        if critical_failures:
            feedback_parts.insert(0, "CRITICAL: " + "; ".join(critical_failures))

        if tracks_found:
            feedback_parts.append(f"Tracks found: {tracks_found[:100]}")

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": {
                "output_file_exists": output_file_exists,
                "correct_row_count": correct_track_count,
                "tracks_validated": known_tracks_matched >= min_tracks_required,
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
