#!/usr/bin/env python3
"""
Verifier for Query Product Sales task in MS SQL Server environment.

Verifies that the agent:
1. Executed a SQL query to find top 10 best-selling products
2. Saved results to the expected output file
3. Results contain correct data from AdventureWorks2022 database
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_query_product_sales(traj, env_info, task_info):
    """
    Verify that a SQL query was executed and results were saved.

    Criteria:
    1. Output file exists (REQUIRED)
    2. Correct row count (~10 rows) (REQUIRED)
    3. Contains known top products from AdventureWorks (REQUIRED)
    4. SQL Server was running
    5. Azure Data Studio was used
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get VLM function for visual verification
    query_vlm = env_info.get('query_vlm')

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_output_file = metadata.get('expected_output_file', '/home/ga/Documents/exports/top_products.csv')
    expected_row_count = metadata.get('expected_row_count', 10)
    known_top_products = metadata.get('known_top_products', [])

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
        mssql_running = result.get('mssql_running', False)
        ads_running = result.get('ads_running', False)
        output_exists = result.get('output_file_exists', False)
        output_row_count = result.get('output_row_count', 0)
        correct_row_count = result.get('correct_row_count', False)
        known_products_found = result.get('known_products_found', 0)
        correct_top_product = result.get('correct_top_product', False)
        products_found = result.get('products_found', '')
        values_match_count = result.get('values_match_count', 0)
        values_validated = result.get('values_validated', False)

        logger.info(f"Result: output_exists={output_exists}, rows={output_row_count}, "
                   f"products_matched={known_products_found}, correct_top={correct_top_product}, "
                   f"values_matched={values_match_count}, values_validated={values_validated}")

        # CRITICAL CHECK 1: Output file must exist
        if not output_exists:
            critical_failures.append(f"Output file not found at {expected_output_file}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"FAILED: Query results not saved. Must export results to: {expected_output_file}",
                "subscores": {
                    "output_file_exists": False,
                    "correct_row_count": False,
                    "products_validated": False,
                    "sql_server_running": mssql_running,
                    "ads_running": ads_running
                }
            }

        # Criterion 1: Output file exists (20 points)
        criteria_passed += 1
        feedback_parts.append("Output file exists")

        # CRITICAL CHECK 2: Correct row count
        if correct_row_count:
            criteria_passed += 1
            feedback_parts.append(f"Row count correct: {output_row_count} products")
        elif output_row_count > 0:
            # Some rows but wrong count
            criteria_passed += 0.3
            feedback_parts.append(f"WRONG COUNT: {output_row_count} rows (expected {expected_row_count})")
        else:
            critical_failures.append("Output file is empty")
            feedback_parts.append("NO DATA: Output file has no rows")

        # CRITICAL CHECK 3: Known products validated
        min_products_required = 2
        if known_products_found >= min_products_required:
            criteria_passed += 1
            feedback_parts.append(f"Product content validated: {known_products_found} known products found")
        elif known_products_found > 0:
            criteria_passed += 0.5
            feedback_parts.append(f"PARTIAL MATCH: Only {known_products_found} known products (need {min_products_required})")
        else:
            critical_failures.append("No known top-selling products found in output")
            feedback_parts.append("INVALID CONTENT: No expected products detected")

        # Criterion 4: SQL Server running (10 points)
        if mssql_running:
            criteria_passed += 0.5
            feedback_parts.append("SQL Server running")
        else:
            feedback_parts.append("SQL Server not detected")

        # Criterion 5: Azure Data Studio running (10 points)
        if ads_running:
            criteria_passed += 0.5
            feedback_parts.append("Azure Data Studio running")
        else:
            feedback_parts.append("Azure Data Studio not detected")

        # Bonus: Correct top product identified
        if correct_top_product:
            criteria_passed += 0.5
            feedback_parts.append("Correct #1 product found")

        # ANTI-GAMING: Database value validation
        # This prevents agents from hardcoding fake values in the CSV
        if values_validated:
            criteria_passed += 0.5
            feedback_parts.append(f"DB validation: {values_match_count}/10 quantities verified")
        elif values_match_count > 0:
            criteria_passed += 0.2
            feedback_parts.append(f"DB validation: PARTIAL ({values_match_count}/10 quantities)")
        elif mssql_running:
            feedback_parts.append("DB validation: quantities not verified against database")

        # VLM verification if available
        vlm_verified = False
        if query_vlm:
            try:
                temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
                try:
                    copy_from_env("/tmp/task_end_screenshot.png", temp_screenshot.name)

                    vlm_prompt = """Analyze this screenshot of Azure Data Studio or similar database tool.

                    Questions:
                    1. Is there a SQL Editor or query panel visible?
                    2. Are there query results visible in a data grid/table?
                    3. Does the visible data appear to show product names and quantities?

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
                            criteria_passed += 0.5
                            feedback_parts.append("VLM: Query results visible")
                finally:
                    os.unlink(temp_screenshot.name)
            except Exception as e:
                logger.warning(f"VLM verification failed: {e}")
                feedback_parts.append("VLM: Unavailable (verification skipped)")
        else:
            feedback_parts.append("VLM: Not configured (visual verification skipped)")

        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        score = min(score, 100)  # Cap at 100

        # STRICT PASS REQUIREMENTS:
        # - Output file must exist
        # - Correct row count (10 rows)
        # - At least 2 known products matched
        # - Database value validation (anti-gaming): at least some values verified
        # - Score >= 70%
        passed = (
            output_exists and
            correct_row_count and
            known_products_found >= min_products_required and
            (values_match_count >= 3 or not mssql_running) and  # Anti-gaming: require value verification if DB is up
            score >= 70
        )

        if critical_failures:
            feedback_parts.insert(0, "CRITICAL: " + "; ".join(critical_failures))

        if products_found:
            feedback_parts.append(f"Products found: {products_found[:100]}")

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": {
                "output_file_exists": output_exists,
                "correct_row_count": correct_row_count,
                "products_validated": known_products_found >= min_products_required,
                "values_validated": values_validated,
                "values_match_count": values_match_count,
                "sql_server_running": mssql_running,
                "ads_running": ads_running,
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
