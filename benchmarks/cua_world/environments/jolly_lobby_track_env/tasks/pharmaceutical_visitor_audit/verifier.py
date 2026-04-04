#!/usr/bin/env python3
"""
Verifier for pharmaceutical_visitor_audit task.

Scoring (100 points total):
- Prerequisite: File /home/ga/Desktop/pharma_healthcare_visitor_audit.csv exists (else score=0)
- Criterion 1: Johnson & Johnson / James Smith present — 20 pts
- Criterion 2: Pfizer Inc / Patricia Williams present — 20 pts
- Criterion 3: Merck & Co / Donald Hall present — 20 pts
- Criterion 4: UnitedHealth Group or Abbott Laboratories present — 20 pts
- Criterion 5: At least 4 of the 5 target companies represented — 20 pts

Passing threshold: 60 points (3 of 5 criteria; i.e. 3 companies found)

Ground truth — December 2025 pharmaceutical/healthcare visitors:
  1. James Smith     / Johnson & Johnson     / Legal         / Business Meeting  (Visitor)
  2. Patricia Williams / Pfizer Inc          / Procurement   / Vendor Meeting    (Vendor)
  3. Elizabeth Moore / UnitedHealth Group    / HR            / Benefits Review   (Visitor)
  4. Donald Hall     / Merck & Co            / Research      / Clinical Trial Update (Visitor)
  5. Sandra Carter   / Abbott Laboratories   / Health & Safety / Medical Device Demo (Vendor)
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_pharmaceutical_visitor_audit(traj, env_info, task_info):
    """Verify the pharmaceutical and healthcare visitor audit report."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        # Step 1: Copy the exported result JSON
        temp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        try:
            copy_from_env(
                "/tmp/pharmaceutical_visitor_audit_result.json", temp_json.name
            )
            with open(temp_json.name, "r") as f:
                result = json.load(f)
        finally:
            os.unlink(temp_json.name)

        # PREREQUISITE: The output file must exist
        if not result.get("file_exists", False):
            return {
                "passed": False,
                "score": 0,
                "feedback": "Output file /home/ga/Desktop/pharma_healthcare_visitor_audit.csv not found. Agent did not create the audit report.",
            }

        # Step 2: Independently copy the actual output file
        content = result.get("file_content", "")
        try:
            temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix=".csv")
            copy_from_env(
                "/home/ga/Desktop/pharma_healthcare_visitor_audit.csv", temp_csv.name
            )
            with open(temp_csv.name, "r", encoding="utf-8", errors="replace") as f:
                content = f.read(6000)
            os.unlink(temp_csv.name)
            logger.info("Used independently-copied file for verification")
        except Exception as e:
            logger.warning(f"Independent file copy failed, using JSON content: {e}")

        content_lower = content.lower()

        score = 0
        feedback_parts = []
        subscores = {}

        # Criterion 1: Johnson & Johnson present (20 points)
        has_jnj = (
            "johnson" in content_lower or "j&j" in content_lower or
            "jnj" in content_lower or "james smith" in content_lower
        )
        if has_jnj:
            score += 20
            subscores["johnson_johnson"] = True
            feedback_parts.append("Johnson & Johnson: FOUND")
        else:
            subscores["johnson_johnson"] = False
            feedback_parts.append("Johnson & Johnson: NOT FOUND")

        # Criterion 2: Pfizer present (20 points)
        has_pfizer = "pfizer" in content_lower or "patricia williams" in content_lower
        if has_pfizer:
            score += 20
            subscores["pfizer"] = True
            feedback_parts.append("Pfizer Inc: FOUND")
        else:
            subscores["pfizer"] = False
            feedback_parts.append("Pfizer Inc: NOT FOUND")

        # Criterion 3: Merck & Co present (20 points)
        has_merck = "merck" in content_lower or "donald hall" in content_lower
        if has_merck:
            score += 20
            subscores["merck"] = True
            feedback_parts.append("Merck & Co: FOUND")
        else:
            subscores["merck"] = False
            feedback_parts.append("Merck & Co: NOT FOUND")

        # Criterion 4: UnitedHealth Group OR Abbott Laboratories present (20 points)
        has_unitedhealth = (
            "unitedhealth" in content_lower or "united health" in content_lower or
            "uhg" in content_lower or "elizabeth moore" in content_lower
        )
        has_abbott = "abbott" in content_lower or "sandra carter" in content_lower
        if has_unitedhealth or has_abbott:
            score += 20
            subscores["unitedhealth_or_abbott"] = True
            companies = []
            if has_unitedhealth:
                companies.append("UnitedHealth Group")
            if has_abbott:
                companies.append("Abbott Laboratories")
            feedback_parts.append(f"UnitedHealth/Abbott: FOUND ({', '.join(companies)})")
        else:
            subscores["unitedhealth_or_abbott"] = False
            feedback_parts.append("UnitedHealth Group and Abbott Laboratories: NEITHER FOUND")

        # Criterion 5: At least 4 of the 5 target companies (20 points)
        companies_found = sum([has_jnj, has_pfizer, has_merck, has_unitedhealth or has_abbott])
        # Note: unitedhealth and abbott together count as at most 2 distinct companies
        has_unitedhealth_alone = has_unitedhealth
        has_abbott_alone = has_abbott
        all_five_count = sum([has_jnj, has_pfizer, has_merck, has_unitedhealth_alone, has_abbott_alone])

        if all_five_count >= 4:
            score += 20
            subscores["four_plus_companies"] = True
            feedback_parts.append(f"4+ of 5 target companies found ({all_five_count}/5)")
        elif all_five_count >= 3:
            score += 10
            subscores["four_plus_companies"] = False
            feedback_parts.append(f"3 of 5 target companies found (need 4+)")
        else:
            subscores["four_plus_companies"] = False
            feedback_parts.append(f"Only {all_five_count} of 5 target companies found")

        passed = score >= 60

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "file_size_bytes": result.get("file_size", 0),
                "companies_found_count": all_five_count,
                "content_preview": content[:300] if content else "",
            },
        }

    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result JSON not found — export_result.sh may not have run",
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid JSON in result file: {e}",
        }
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
