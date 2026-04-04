#!/usr/bin/env python3
"""
Verifier for Create Customer Orders View task in MS SQL Server environment.

Verifies that the agent:
1. Created a view called vw_CustomerOrderSummary
2. The view has the required columns
3. The view returns data (joins are working correctly)
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_customer_orders_view(traj, env_info, task_info):
    """
    Verify that the view was created correctly.

    Criteria:
    1. View exists (REQUIRED)
    2. Has required columns (REQUIRED)
    3. Returns reasonable row count (REQUIRED)
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
    expected_view_name = metadata.get('expected_view_name', 'vw_CustomerOrderSummary')
    required_columns = metadata.get('required_columns', [])
    min_rows = metadata.get('min_rows', 100)

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/view_result.json", temp_result.name)
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
        view_exists = result.get('view_exists', False)
        view_column_count = result.get('view_column_count', 0)
        has_required_columns = result.get('has_required_columns', False)
        correct_data_types = result.get('correct_data_types', False)
        view_row_count = result.get('view_row_count', 0)
        reasonable_row_count = result.get('reasonable_row_count', False)
        columns_found = result.get('columns_found', '')
        column_types = result.get('column_types', '')

        # ANTI-GAMING: Data validation fields
        data_validated = result.get('data_validated', False)
        data_match_count = result.get('data_match_count', 0)
        orders_validated = result.get('orders_validated', False)

        logger.info(f"Result: view_exists={view_exists}, columns={view_column_count}, "
                   f"rows={view_row_count}, has_required_cols={has_required_columns}, "
                   f"correct_types={correct_data_types}, data_validated={data_validated}, "
                   f"orders_validated={orders_validated}")

        # CRITICAL CHECK 1: View must exist
        if not view_exists:
            critical_failures.append(f"View '{expected_view_name}' was not created")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"FAILED: View '{expected_view_name}' does not exist in the database",
                "subscores": {
                    "view_exists": False,
                    "has_required_columns": False,
                    "has_data": False,
                    "sql_server_running": mssql_running,
                    "ads_running": ads_running
                }
            }

        # Criterion 1: View exists (25 points)
        criteria_passed += 1
        feedback_parts.append(f"View '{expected_view_name}' exists")

        # CRITICAL CHECK 2: Has required columns
        if has_required_columns:
            criteria_passed += 1
            feedback_parts.append(f"View has required columns: {columns_found}")
        elif view_column_count > 0:
            # Some columns but not all required
            criteria_passed += 0.5
            feedback_parts.append(f"PARTIAL: View has {view_column_count} columns but missing some required ones")
        else:
            critical_failures.append("View has no columns")
            feedback_parts.append("ERROR: View has no columns")

        # CHECK 2.5: Column data types are correct
        if correct_data_types:
            criteria_passed += 0.5
            feedback_parts.append("Column data types are correct")
        else:
            feedback_parts.append(f"PARTIAL: Some column data types may be incorrect ({column_types})")

        # CRITICAL CHECK 3: View returns data
        if reasonable_row_count:
            criteria_passed += 1
            feedback_parts.append(f"View returns {view_row_count} rows (joins work correctly)")
        elif view_row_count > 0:
            criteria_passed += 0.5
            feedback_parts.append(f"PARTIAL: View returns only {view_row_count} rows (expected >= {min_rows})")
        else:
            critical_failures.append("View returns no data (joins may be incorrect)")
            feedback_parts.append("ERROR: View returns 0 rows")

        # ANTI-GAMING CHECK: Validate view returns REAL customer data
        # This prevents agents from creating fake views with SELECT 1 AS CustomerID, etc.
        if data_validated:
            criteria_passed += 0.5
            feedback_parts.append(f"Data validation: {data_match_count}/5 CustomerIDs verified in Sales.Customer")
        elif data_match_count > 0:
            criteria_passed += 0.2
            feedback_parts.append(f"Data validation: PARTIAL ({data_match_count}/5 CustomerIDs verified)")
        elif mssql_running and view_exists:
            feedback_parts.append("Data validation: CustomerIDs not verified against Sales.Customer")

        # ANTI-GAMING CHECK: Validate TotalOrders count is accurate
        if orders_validated:
            criteria_passed += 0.5
            feedback_parts.append("Orders validation: TotalOrders count matches SalesOrderHeader")
        elif mssql_running and view_exists:
            feedback_parts.append("Orders validation: TotalOrders count not verified")

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
                    2. Is there a CREATE VIEW statement visible?
                    3. Are there query results or a success message visible?

                    Respond with "VERIFIED" if you can see evidence of view creation,
                    or "NOT VERIFIED" otherwise.
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
                            feedback_parts.append("VLM: View creation confirmed visually")
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
        # - View must exist
        # - Must have required columns
        # - Must return reasonable data
        # - Data must be validated against real tables (anti-gaming)
        # - Score >= 70%
        passed = (
            view_exists and
            has_required_columns and
            reasonable_row_count and
            (data_validated or not mssql_running) and  # Anti-gaming: require data validation if DB is up
            score >= 70
        )

        if critical_failures:
            feedback_parts.insert(0, "CRITICAL: " + "; ".join(critical_failures))

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": {
                "view_exists": view_exists,
                "has_required_columns": has_required_columns,
                "correct_data_types": correct_data_types,
                "has_data": reasonable_row_count,
                "data_validated": data_validated,
                "data_match_count": data_match_count,
                "orders_validated": orders_validated,
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
