#!/usr/bin/env python3
"""
Verifier for december_visitor_badge_breakdown task.

Scoring (100 points total):
- Prerequisite: File /home/ga/Desktop/dec2025_visitor_analysis.csv exists (else score=0)
- Criterion 1: Total visitor count approximately correct (38-42 range) — 25 pts
- Criterion 2: Badge type counts approximately correct (Visitor~16, Contractor~12, Vendor~12) — 25 pts
- Criterion 3: Top departments identified (Marketing, Procurement, Facilities) — 30 pts
- Criterion 4: File is substantive (>200 bytes) — 20 pts

Passing threshold: 70 points

Ground truth — December 2025 visitor data:
  Total: 40 visits
  Visitor badge:    16
  Contractor badge: 12
  Vendor badge:     12

  Top departments (tied at 3 each):
  - Marketing   (3): P&G, Facebook Meta, Walt Disney
  - Procurement (3): Pfizer, Northrop Grumman, Dow Chemical
  - Facilities  (3): Ford, Caterpillar, Honeywell
"""

import os
import re
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _extract_numbers(text):
    """Extract all integers from text."""
    return [int(n) for n in re.findall(r"\b(\d+)\b", text)]


def verify_december_visitor_badge_breakdown(traj, env_info, task_info):
    """Verify the December 2025 visitor traffic analysis report."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        # Step 1: Copy the exported result JSON
        temp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        try:
            copy_from_env(
                "/tmp/december_visitor_badge_breakdown_result.json", temp_json.name
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
                "feedback": "Output file /home/ga/Desktop/dec2025_visitor_analysis.csv not found. Agent did not create the analysis report.",
            }

        # Step 2: Independently copy the actual output file
        content = result.get("file_content", "")
        try:
            temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix=".csv")
            copy_from_env(
                "/home/ga/Desktop/dec2025_visitor_analysis.csv", temp_csv.name
            )
            with open(temp_csv.name, "r", encoding="utf-8", errors="replace") as f:
                content = f.read(6000)
            os.unlink(temp_csv.name)
            logger.info("Used independently-copied file for verification")
        except Exception as e:
            logger.warning(f"Independent file copy failed, using JSON content: {e}")

        content_lower = content.lower()
        file_size = result.get("file_size", len(content))
        all_numbers = _extract_numbers(content)

        score = 0
        feedback_parts = []
        subscores = {}

        # Criterion 1: Total visitor count approximately correct (25 points)
        # Expected: 40 total December 2025 visitors (accept 38-42)
        total_count_correct = any(38 <= n <= 42 for n in all_numbers)
        if total_count_correct:
            score += 25
            subscores["total_count"] = True
            found_near_40 = [n for n in all_numbers if 38 <= n <= 42]
            feedback_parts.append(f"Total count approximately correct (found {found_near_40})")
        else:
            subscores["total_count"] = False
            feedback_parts.append(f"Total count not found in 38-42 range (numbers in file: {all_numbers[:10]})")

        # Criterion 2: Badge type counts approximately correct (25 points)
        # Visitor~16, Contractor~12, Vendor~12 (accept ±2 for each)
        has_visitor_count = any(14 <= n <= 18 for n in all_numbers)
        has_contractor_count = any(10 <= n <= 14 for n in all_numbers)
        has_vendor_count = any(10 <= n <= 14 for n in all_numbers)
        # Also check that badge type keywords appear
        has_visitor_kw = "visitor" in content_lower
        has_contractor_kw = "contractor" in content_lower
        has_vendor_kw = "vendor" in content_lower

        badge_breakdown_ok = (
            (has_visitor_count and has_visitor_kw) or
            (has_contractor_count and has_contractor_kw) or
            (has_vendor_count and has_vendor_kw)
        )
        badge_keywords_all = has_visitor_kw and has_contractor_kw and has_vendor_kw

        if badge_keywords_all and (has_visitor_count or has_contractor_count or has_vendor_count):
            score += 25
            subscores["badge_breakdown"] = True
            feedback_parts.append("Badge type breakdown found (Visitor, Contractor, Vendor with counts)")
        elif badge_keywords_all:
            score += 15
            subscores["badge_breakdown"] = False
            feedback_parts.append("Badge type keywords present but no matching counts found")
        elif badge_breakdown_ok:
            score += 10
            subscores["badge_breakdown"] = False
            feedback_parts.append("Partial badge breakdown found")
        else:
            subscores["badge_breakdown"] = False
            feedback_parts.append("Badge type breakdown (Visitor/Contractor/Vendor) not found")

        # Criterion 3: Top departments identified (30 points)
        # Expected top departments: Marketing, Procurement, Facilities (all tied at 3)
        has_marketing = "marketing" in content_lower
        has_procurement = "procurement" in content_lower
        has_facilities = "facilities" in content_lower
        top_depts_found = sum([has_marketing, has_procurement, has_facilities])

        if top_depts_found == 3:
            score += 30
            subscores["top_departments"] = True
            feedback_parts.append("All 3 top departments identified (Marketing, Procurement, Facilities)")
        elif top_depts_found == 2:
            score += 20
            subscores["top_departments"] = False
            found = [d for d, f in [("Marketing", has_marketing), ("Procurement", has_procurement), ("Facilities", has_facilities)] if f]
            feedback_parts.append(f"2/3 top departments found: {found}")
        elif top_depts_found == 1:
            score += 10
            subscores["top_departments"] = False
            feedback_parts.append("Only 1 top department found (need Marketing, Procurement, Facilities)")
        else:
            subscores["top_departments"] = False
            feedback_parts.append("Top departments (Marketing, Procurement, Facilities) not found")

        # Criterion 4: File is substantive (20 points)
        if file_size > 200:
            score += 20
            subscores["file_substantive"] = True
            feedback_parts.append(f"File is substantive ({file_size} bytes)")
        elif file_size > 50:
            score += 10
            subscores["file_substantive"] = False
            feedback_parts.append(f"File is minimal ({file_size} bytes) — expected fuller report")
        else:
            subscores["file_substantive"] = False
            feedback_parts.append(f"File is too small ({file_size} bytes)")

        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "file_size_bytes": file_size,
                "numbers_found": all_numbers[:15],
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
