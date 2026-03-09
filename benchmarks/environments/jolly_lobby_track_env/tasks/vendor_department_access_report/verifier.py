#!/usr/bin/env python3
"""
Verifier for vendor_department_access_report task.

Scoring (100 points total):
- Prerequisite: File /home/ga/Desktop/vendor_dept_access_dec2025.csv exists (else score=0)
- Criterion 1: "Facilities" identified as top/leading department — 30 pts
- Criterion 2: All 3 Facilities vendors present (Ford, Caterpillar, Honeywell) — 25 pts
- Criterion 3: File is substantive (>150 bytes) reflecting a real report — 20 pts
- Criterion 4: Multiple departments represented OR total vendor count ~12 — 25 pts

Passing threshold: 70 points

Ground truth (December 2025 vendors by department):
  Facilities (3):   Matthew Rodriguez/Ford, Betty Walker/Caterpillar, Kenneth King/Honeywell
  Procurement (2):  Patricia Williams/Pfizer, Mark Mitchell/Dow Chemical
  Logistics (2):    Sarah Thompson/Walmart, Steven Young/UPS
  Compliance (1):   William Wilson/Boeing
  Legal (1):        Charles White/Lockheed Martin
  R&D (1):          Anthony Lee/3M
  Health & Safety(1): Sandra Carter/Abbott
  Supply Chain (1): Kimberly Baker/PepsiCo
  Total: 12 vendors
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_vendor_department_access_report(traj, env_info, task_info):
    """Verify the December 2025 vendor department access report."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        # Step 1: Copy the exported result JSON
        temp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        try:
            copy_from_env(
                "/tmp/vendor_department_access_report_result.json", temp_json.name
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
                "feedback": "Output file /home/ga/Desktop/vendor_dept_access_dec2025.csv not found. Agent did not create the vendor access report.",
            }

        # Step 2: Independently copy the actual output file for anti-tamper verification
        content = result.get("file_content", "")
        try:
            temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix=".csv")
            copy_from_env(
                "/home/ga/Desktop/vendor_dept_access_dec2025.csv", temp_csv.name
            )
            with open(temp_csv.name, "r", encoding="utf-8", errors="replace") as f:
                content = f.read(6000)
            os.unlink(temp_csv.name)
            logger.info("Used independently-copied file for verification")
        except Exception as e:
            logger.warning(f"Independent file copy failed, using JSON content: {e}")

        content_lower = content.lower()
        file_size = result.get("file_size", len(content))

        score = 0
        feedback_parts = []
        subscores = {}

        # Criterion 1: "Facilities" as the top/leading department (30 points)
        # Facilities had 3 vendor visits — the highest of any department
        has_facilities = "facilities" in content_lower
        if has_facilities:
            score += 30
            subscores["facilities_top_dept"] = True
            feedback_parts.append("Facilities department: FOUND (correct top vendor dept)")
        else:
            subscores["facilities_top_dept"] = False
            feedback_parts.append("Facilities department: NOT FOUND (should be top with 3 vendor visits)")

        # Criterion 2: All three Facilities vendors present (25 points)
        # Ford Motor Company, Caterpillar Inc, Honeywell International
        has_ford = "ford" in content_lower
        has_caterpillar = "caterpillar" in content_lower
        has_honeywell = "honeywell" in content_lower
        facilities_vendors_found = sum([has_ford, has_caterpillar, has_honeywell])

        if facilities_vendors_found == 3:
            score += 25
            subscores["facilities_vendors_complete"] = True
            feedback_parts.append("All 3 Facilities vendors (Ford, Caterpillar, Honeywell): ALL FOUND")
        elif facilities_vendors_found == 2:
            score += 15
            subscores["facilities_vendors_complete"] = False
            found = [v for v, f in [("Ford", has_ford), ("Caterpillar", has_caterpillar), ("Honeywell", has_honeywell)] if f]
            feedback_parts.append(f"2/3 Facilities vendors found: {found}")
        elif facilities_vendors_found == 1:
            score += 8
            subscores["facilities_vendors_complete"] = False
            feedback_parts.append("Only 1/3 Facilities vendors found in report")
        else:
            subscores["facilities_vendors_complete"] = False
            feedback_parts.append("No Facilities vendors (Ford, Caterpillar, Honeywell) found in report")

        # Criterion 3: File is substantive — real report (20 points)
        if file_size > 150:
            score += 20
            subscores["file_substantive"] = True
            feedback_parts.append(f"File is substantive ({file_size} bytes)")
        else:
            subscores["file_substantive"] = False
            feedback_parts.append(f"File too small ({file_size} bytes) — may not be a complete report")

        # Criterion 4: Multiple departments or total count ~12 (25 points)
        # Check for multiple department names OR the number 12
        dept_names = [
            "procurement", "logistics", "compliance", "legal", "r&d",
            "health", "supply chain", "safety"
        ]
        dept_count = sum(1 for d in dept_names if d in content_lower)
        has_count_12 = "12" in content_lower or "twelve" in content_lower

        if dept_count >= 3 or has_count_12:
            score += 25
            subscores["breadth_covered"] = True
            feedback_parts.append(f"Report covers multiple departments (found {dept_count} other dept names)")
        elif dept_count >= 1:
            score += 12
            subscores["breadth_covered"] = False
            feedback_parts.append(f"Report partially covers departments ({dept_count} found, expected 3+)")
        else:
            subscores["breadth_covered"] = False
            feedback_parts.append("Report does not show multi-department breakdown")

        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "file_size_bytes": file_size,
                "content_preview": content[:300] if content else "",
                "facilities_vendors_found": facilities_vendors_found,
                "dept_names_found": dept_count,
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
