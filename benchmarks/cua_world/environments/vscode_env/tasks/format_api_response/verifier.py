#!/usr/bin/env python3
"""
Verifier for Format API Response task
"""

import sys
import os
import logging
import tempfile
import json
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import check_file_exists, read_file_content, cleanup_verification_temp

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_format_api_response(traj, env_info, task_info):
    """
    Verify that API response formatting task was completed correctly.

    Checks:
    1. api_response.json is formatted (multi-line, >10 lines, valid JSON)
    2. price_summary.json exists with correct structure and values
    3. API_STRUCTURE.md exists with meaningful documentation
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    workspace = "/home/ga/workspace/api_project"
    temp_dir = tempfile.mkdtemp(prefix='api_verify_')

    try:
        feedback_parts = []
        criteria_passed = 0
        total_criteria = 3

        # ============================================================
        # Criterion 1: Original file is formatted (multi-line)
        # ============================================================
        original_path = f"{workspace}/api_response.json"
        local_original = os.path.join(temp_dir, "api_response.json")

        try:
            copy_from_env(original_path, local_original)

            if not os.path.exists(local_original) or os.path.getsize(local_original) == 0:
                feedback_parts.append("❌ api_response.json not found or empty")
                return _build_result(False, criteria_passed, total_criteria, feedback_parts)

            with open(local_original, 'r', encoding='utf-8') as f:
                content = f.read()
                lines = content.split('\n')

            # Check if formatted (has multiple lines with indentation)
            if len(lines) < 10:
                feedback_parts.append(f"❌ api_response.json not formatted - only {len(lines)} line(s), expected 10+")
                return _build_result(False, criteria_passed, total_criteria, feedback_parts)

            # Check for indentation (formatted JSON should have spaces/tabs)
            has_indentation = any(line.startswith((' ', '\t')) for line in lines if line.strip())
            if not has_indentation:
                feedback_parts.append("❌ api_response.json lacks proper indentation")
                return _build_result(False, criteria_passed, total_criteria, feedback_parts)

            # Verify valid JSON
            try:
                data = json.loads(content)
                feedback_parts.append(f"✅ api_response.json formatted correctly ({len(lines)} lines)")
                criteria_passed += 1
            except json.JSONDecodeError as e:
                feedback_parts.append(f"❌ api_response.json is not valid JSON: {str(e)}")
                return _build_result(False, criteria_passed, total_criteria, feedback_parts)

        except Exception as e:
            feedback_parts.append(f"❌ Error checking api_response.json: {str(e)}")
            return _build_result(False, criteria_passed, total_criteria, feedback_parts)

        # ============================================================
        # Criterion 2: Summary file exists and has correct structure
        # ============================================================
        summary_path = f"{workspace}/price_summary.json"
        local_summary = os.path.join(temp_dir, "price_summary.json")

        try:
            copy_from_env(summary_path, local_summary)

            if not os.path.exists(local_summary) or os.path.getsize(local_summary) == 0:
                feedback_parts.append("❌ price_summary.json not found or empty")
                return _build_result(False, criteria_passed, total_criteria, feedback_parts)

            with open(local_summary, 'r', encoding='utf-8') as f:
                try:
                    summary = json.load(f)
                except json.JSONDecodeError as e:
                    feedback_parts.append(f"❌ price_summary.json is not valid JSON: {str(e)}")
                    return _build_result(False, criteria_passed, total_criteria, feedback_parts)

            # Check required fields
            errors = []

            # Check timestamp
            if "timestamp" not in summary:
                errors.append("missing 'timestamp' field")
            elif summary["timestamp"] != 1703001234567:
                errors.append(f"timestamp incorrect (expected 1703001234567, got {summary['timestamp']})")

            # Check prices structure
            if "prices" not in summary:
                errors.append("missing 'prices' field")
            else:
                prices = summary["prices"]

                # Check BTC prices
                if "BTC" not in prices:
                    errors.append("missing BTC in prices")
                else:
                    btc = prices["BTC"]
                    if not isinstance(btc, dict):
                        errors.append("BTC should be an object")
                    else:
                        if "usd" not in btc:
                            errors.append("missing BTC.usd")
                        elif not isinstance(btc["usd"], (int, float)) or abs(btc["usd"] - 43250.75) > 1:
                            errors.append(f"BTC.usd incorrect (expected ~43250.75, got {btc.get('usd')})")

                        if "eur" not in btc:
                            errors.append("missing BTC.eur")
                        elif not isinstance(btc["eur"], (int, float)) or abs(btc["eur"] - 39876.23) > 1:
                            errors.append(f"BTC.eur incorrect (expected ~39876.23, got {btc.get('eur')})")

                # Check ETH prices
                if "ETH" not in prices:
                    errors.append("missing ETH in prices")
                else:
                    eth = prices["ETH"]
                    if not isinstance(eth, dict):
                        errors.append("ETH should be an object")
                    else:
                        if "usd" not in eth:
                            errors.append("missing ETH.usd")
                        elif not isinstance(eth["usd"], (int, float)) or abs(eth["usd"] - 2287.45) > 1:
                            errors.append(f"ETH.usd incorrect (expected ~2287.45, got {eth.get('usd')})")

                        if "eur" not in eth:
                            errors.append("missing ETH.eur")
                        elif not isinstance(eth["eur"], (int, float)) or abs(eth["eur"] - 2108.92) > 1:
                            errors.append(f"ETH.eur incorrect (expected ~2108.92, got {eth.get('eur')})")

            if errors:
                feedback_parts.append(f"❌ price_summary.json has issues: {'; '.join(errors)}")
                return _build_result(False, criteria_passed, total_criteria, feedback_parts)

            feedback_parts.append("✅ price_summary.json created with correct structure and values")
            criteria_passed += 1

        except Exception as e:
            feedback_parts.append(f"❌ Error checking price_summary.json: {str(e)}")
            return _build_result(False, criteria_passed, total_criteria, feedback_parts)

        # ============================================================
        # Criterion 3: Documentation file exists and has content
        # ============================================================
        doc_path = f"{workspace}/API_STRUCTURE.md"
        local_doc = os.path.join(temp_dir, "API_STRUCTURE.md")

        try:
            copy_from_env(doc_path, local_doc)

            if not os.path.exists(local_doc) or os.path.getsize(local_doc) == 0:
                feedback_parts.append("❌ API_STRUCTURE.md not found or empty")
                return _build_result(False, criteria_passed, total_criteria, feedback_parts)

            with open(local_doc, 'r', encoding='utf-8') as f:
                doc_content = f.read()

            # Check for minimum content length
            if len(doc_content.strip()) < 100:
                feedback_parts.append(f"❌ API_STRUCTURE.md too short ({len(doc_content)} chars, expected 100+)")
                return _build_result(False, criteria_passed, total_criteria, feedback_parts)

            # Check for relevant keywords
            doc_lower = doc_content.lower()
            keywords = ["timestamp", "market", "price", "structure", "api", "data", "currency"]
            found_keywords = [kw for kw in keywords if kw in doc_lower]

            if len(found_keywords) < 2:
                feedback_parts.append(f"❌ API_STRUCTURE.md lacks relevant content (found keywords: {found_keywords})")
                return _build_result(False, criteria_passed, total_criteria, feedback_parts)

            feedback_parts.append(f"✅ API_STRUCTURE.md created with documentation ({len(doc_content)} chars)")
            criteria_passed += 1

        except Exception as e:
            feedback_parts.append(f"❌ Error checking API_STRUCTURE.md: {str(e)}")
            return _build_result(False, criteria_passed, total_criteria, feedback_parts)

        # ============================================================
        # All checks passed
        # ============================================================
        return _build_result(True, criteria_passed, total_criteria, feedback_parts)

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_verification_temp(temp_dir)


def _build_result(passed, criteria_passed, total_criteria, feedback_parts):
    """Helper to build consistent result dictionary"""
    score = int((criteria_passed / total_criteria) * 100)
    feedback = " | ".join(feedback_parts)

    if passed and criteria_passed == total_criteria:
        feedback_parts.append("🎉 All tasks completed successfully")
        feedback = " | ".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
