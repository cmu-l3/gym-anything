#!/usr/bin/env python3
"""
Verifier for Validate Data Pipeline task
"""

import sys
import os
import json
import csv
import re
import logging
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import cleanup_verification_temp

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_validation_task(traj, env_info, task_info):
    """
    Verify the data validation task was completed correctly.
    
    Success criteria:
    1. Test CSV file created with at least 3 orders (0.20)
    2. Test data includes at least one edge case (0.10)
    3. JSON report generated successfully (0.20)
    4. Validation document (VALIDATION.md) created with analysis (0.25)
    5. Code modified with validation/debugging logic (0.15)
    6. Bug identified in code or documentation (0.10)
    
    Pass threshold: 0.70
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='validate_pipeline_verify_')

    try:
        # Copy exported files from /tmp
        local_csv = os.path.join(temp_dir, "orders.csv")
        local_json = os.path.join(temp_dir, "report.json")
        local_validation = os.path.join(temp_dir, "VALIDATION.md")
        local_script = os.path.join(temp_dir, "process_orders.py")
        local_test = os.path.join(temp_dir, "test_orders.py")

        # Copy files with error handling
        files_copied = {}
        for container_path, local_path, name in [
            ("/tmp/orders.csv", local_csv, "orders.csv"),
            ("/tmp/report.json", local_json, "report.json"),
            ("/tmp/VALIDATION.md", local_validation, "VALIDATION.md"),
            ("/tmp/process_orders.py", local_script, "process_orders.py"),
            ("/tmp/test_orders.py", local_test, "test_orders.py"),
        ]:
            try:
                copy_from_env(container_path, local_path)
                if os.path.exists(local_path) and os.path.getsize(local_path) > 0:
                    files_copied[name] = local_path
            except Exception as e:
                logger.warning(f"Failed to copy {name}: {e}")

        score = 0.0
        feedback_parts = []

        # Check 1: Test CSV created with sufficient data (0.20)
        csv_rows = []
        if "orders.csv" in files_copied:
            try:
                with open(local_csv, 'r', encoding='utf-8') as f:
                    content = f.read().strip()
                    # Check if it's not empty or error message
                    if content and "not found" not in content.lower():
                        reader = csv.DictReader(content.splitlines())
                        csv_rows = list(reader)
                        
                        if len(csv_rows) >= 3:
                            score += 0.20
                            feedback_parts.append(f"✅ Test CSV created with {len(csv_rows)} orders")
                        elif len(csv_rows) > 0:
                            score += 0.10
                            feedback_parts.append(f"⚠️ CSV has only {len(csv_rows)} rows (need ≥3)")
                        else:
                            feedback_parts.append("❌ CSV file is empty")
                    else:
                        feedback_parts.append("❌ CSV file not properly created")
            except Exception as e:
                feedback_parts.append(f"❌ Error reading CSV: {str(e)[:50]}")
        else:
            feedback_parts.append("❌ orders.csv not created")

        # Check 2: Test data includes edge cases (0.10)
        if csv_rows:
            has_edge_case = False
            edge_case_types = []
            
            for row in csv_rows:
                # Check for various edge cases
                items = row.get('Items', '')
                total = row.get('TotalAmount', '')
                customer = row.get('CustomerName', '').strip()
                
                if not items or items == '""' or items == "''":
                    has_edge_case = True
                    edge_case_types.append("empty items")
                if '$0' in total or total.strip() == '$0.00':
                    has_edge_case = True
                    edge_case_types.append("zero amount")
                if not customer or customer == '':
                    has_edge_case = True
                    edge_case_types.append("empty customer")
                if 'special' in customer.lower() or any(c in customer for c in ['!', '@', '#']):
                    has_edge_case = True
                    edge_case_types.append("special chars")
            
            if has_edge_case:
                score += 0.10
                feedback_parts.append(f"✅ Edge cases included: {', '.join(set(edge_case_types))}")
            else:
                feedback_parts.append("⚠️ No obvious edge cases detected")

        # Check 3: JSON report generated successfully (0.20)
        if "report.json" in files_copied:
            try:
                with open(local_json, 'r', encoding='utf-8') as f:
                    content = f.read().strip()
                    if content and content != "{}":
                        report = json.loads(content)
                        
                        if 'orders' in report and len(report.get('orders', [])) > 0:
                            score += 0.15
                            feedback_parts.append(f"✅ JSON report generated with {len(report['orders'])} orders")
                            
                            # Check structure quality
                            if all(key in report for key in ['processed_date', 'total_orders', 'orders']):
                                score += 0.05
                                feedback_parts.append("✅ Report has proper structure")
                        else:
                            feedback_parts.append("❌ JSON report empty or malformed")
                    else:
                        feedback_parts.append("❌ report.json not generated")
            except json.JSONDecodeError as e:
                feedback_parts.append(f"❌ Invalid JSON: {str(e)[:50]}")
            except Exception as e:
                feedback_parts.append(f"❌ Error reading JSON: {str(e)[:50]}")
        else:
            feedback_parts.append("❌ report.json not found")

        # Check 4: Validation document created (0.25)
        if "VALIDATION.md" in files_copied:
            try:
                with open(local_validation, 'r', encoding='utf-8') as f:
                    content = f.read().strip()
                    
                    if content and len(content) > 50:
                        score += 0.15
                        feedback_parts.append("✅ Validation document created")
                        
                        content_lower = content.lower()
                        
                        # Check for validation keywords
                        validation_keywords = ['total', 'correct', 'bug', 'issue', 'test', 'verify', 'validate', 'result', 'expected']
                        found_keywords = sum(1 for kw in validation_keywords if kw in content_lower)
                        
                        if found_keywords >= 3:
                            score += 0.05
                            feedback_parts.append("✅ Validation document has analysis")
                        
                        # Check if specific values/calculations mentioned
                        if re.search(r'\$\d+\.?\d*|\d+\.\d+', content):
                            score += 0.05
                            feedback_parts.append("✅ Document includes specific values")
                        
                        # Check for identifying the bug
                        if any(term in content_lower for term in ['totalamount', 'total amount', 'mismatch', 'discrepancy', 'incorrect total']):
                            feedback_parts.append("✅ Identified total calculation issue")
                    else:
                        feedback_parts.append("⚠️ Validation document too short")
            except Exception as e:
                feedback_parts.append(f"❌ Error reading validation doc: {str(e)[:50]}")
        else:
            feedback_parts.append("❌ VALIDATION.md not created")

        # Check 5: Code modified with validation logic (0.15)
        if "process_orders.py" in files_copied:
            try:
                with open(local_script, 'r', encoding='utf-8') as f:
                    code = f.read()
                    
                    # Look for validation-related additions
                    validation_indicators = [
                        'assert' in code.lower() and code.count('assert') > 0,
                        code.count('print(') > 1,  # More than the original print
                        'debug' in code.lower(),
                        'validate' in code.lower(),
                        '# bug' in code.lower() or '# issue' in code.lower() or '# fix' in code.lower(),
                        'logging' in code,
                        'totalamount' in code.lower() and 'totalamount' not in "# BUG: Total is calculated but doesn't match 'TotalAmount' field"
                    ]
                    
                    if any(validation_indicators):
                        score += 0.15
                        feedback_parts.append("✅ Code modified with validation/debugging")
                    else:
                        feedback_parts.append("⚠️ No clear validation logic added to code")
            except Exception as e:
                feedback_parts.append(f"❌ Error reading script: {str(e)[:50]}")

        # Check 6: Alternative - separate test file created (bonus 0.10)
        if "test_orders.py" in files_copied:
            try:
                with open(local_test, 'r', encoding='utf-8') as f:
                    content = f.read().strip()
                    if content and len(content) > 20:
                        score += 0.10
                        feedback_parts.append("✅ Created separate test script")
            except:
                pass

        # Ensure score doesn't exceed 1.0
        score = min(score, 1.0)
        
        # Success threshold: 0.70
        passed = score >= 0.70

        if passed:
            feedback_parts.append(f"\n✅ Task completed! Score: {score:.2f}/1.00")
        else:
            feedback_parts.append(f"\n❌ Task incomplete. Score: {score:.2f}/1.00 (need ≥0.70)")

        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": int(score * 100),
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_verification_temp(temp_dir)
