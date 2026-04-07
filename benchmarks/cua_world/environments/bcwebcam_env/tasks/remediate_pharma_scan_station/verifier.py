"""
Verifier for remediate_pharma_scan_station task.

Scores two dimensions:
  1. INI configuration (30 pts)  — did the agent fix bcWebCam settings?
  2. Audit report CSV  (70 pts)  — did the agent classify and cross-reference correctly?

Pass threshold: 55 / 100
"""

import csv
import io
import json
import os
import tempfile


def verify_remediate_pharma_scan_station(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get("metadata", {})

    # ── pull result JSON from VM ─────────────────────────────────────
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env(
            "C:\\Windows\\Temp\\remediate_pharma_scan_station_result.json",
            tmp.name,
        )
        with open(tmp.name, "r", encoding="utf-8-sig") as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read result JSON: {e}",
        }
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []
    details = {}

    # ══════════════════════════════════════════════════════════════════
    # SECTION 1 — INI configuration (30 pts)
    # ══════════════════════════════════════════════════════════════════
    if not result.get("ini_exists"):
        feedback.append("INI file not found")
    else:
        general = result.get("general", {})

        # --- barcode types (21 pts) ---
        bd = result.get("barcode_d_type", "0")
        if bd and bd != "0":
            score += 5
            details["barcode_d_enabled"] = True
        else:
            feedback.append("DataMatrix not enabled ([BarcodeD] Type should be nonzero)")
            details["barcode_d_enabled"] = False

        for key, label, pts in [
            ("barcode_l_type", "Linear",  4),
            ("barcode_p_type", "QR Code", 4),
            ("barcode_a_type", "Aztec",   4),
            ("barcode_pn_type", "PDF417", 4),
        ]:
            actual = result.get(key, "")
            expected = metadata.get(f"expected_{key}", "0")
            if actual == expected:
                score += pts
                details[key] = "correct"
            else:
                feedback.append(f"{label} not disabled ({key}={actual!r}, expected {expected!r})")
                details[key] = f"wrong ({actual!r})"

        # --- general settings (9 pts) ---
        checks = [
            ("Beep",            metadata.get("expected_beep", "False"),             2, True),
            ("BcGracePeriod",   metadata.get("expected_bc_grace_period", "5"),      2, False),
            ("SendKeysPostfix", metadata.get("expected_send_keys_postfix", ""),     2, False),
            ("Opacity",         metadata.get("expected_opacity", "0,65"),           3, False),
        ]
        for key, expected, pts, case_insensitive in checks:
            actual = general.get(key, "")
            if actual is None:
                actual = ""
            match = (actual.lower() == expected.lower()) if case_insensitive else (actual == expected)
            if match:
                score += pts
                details[f"general_{key}"] = "correct"
            else:
                feedback.append(f"[General] {key}={actual!r}, expected {expected!r}")
                details[f"general_{key}"] = f"wrong ({actual!r})"

    ini_score = score  # snapshot for subscores

    # ══════════════════════════════════════════════════════════════════
    # SECTION 2 — Audit report CSV (70 pts)
    # ══════════════════════════════════════════════════════════════════
    csv_score = 0

    if not result.get("audit_report_exists"):
        feedback.append("audit_report.csv not found")
    else:
        raw_content = result.get("audit_report_content", "")
        if not raw_content or not raw_content.strip():
            feedback.append("audit_report.csv is empty")
        else:
            # --- parse CSV ---
            try:
                reader = csv.DictReader(io.StringIO(raw_content.strip()))
                rows = list(reader)
                headers = [h.strip().lower() for h in (reader.fieldnames or [])]
            except Exception as e:
                feedback.append(f"CSV parse error: {e}")
                rows = []
                headers = []

            # --- header check (5 pts) ---
            required_headers = {"timestamp", "rawdata", "barcodetype", "gtin", "productname", "action"}
            if required_headers.issubset(set(headers)):
                csv_score += 5
                details["csv_headers"] = "correct"
            else:
                missing = required_headers - set(headers)
                feedback.append(f"CSV missing headers: {missing}")
                details["csv_headers"] = f"missing {missing}"

            # --- row count (5 pts) ---
            expected_rows = metadata.get("expected_row_count", 10)
            if len(rows) == expected_rows:
                csv_score += 5
                details["csv_row_count"] = "correct"
            else:
                feedback.append(f"CSV has {len(rows)} data rows, expected {expected_rows}")
                details["csv_row_count"] = f"wrong ({len(rows)})"

            # --- per-row content checks ---
            expected_actions = metadata.get("expected_actions", [])
            expected_types = metadata.get("expected_barcode_types", [])
            expected_gtins = metadata.get("expected_gtins", [])

            action_correct = 0
            type_correct = 0
            gtin_correct = 0

            n = min(len(rows), len(expected_actions))
            for i in range(n):
                row = rows[i]
                # normalize keys to lowercase for robust matching
                row_lower = {k.strip().lower(): v.strip() if v else "" for k, v in row.items()}

                # Action (1.5 pts each, 15 pts total)
                actual_action = row_lower.get("action", "").upper()
                if actual_action == expected_actions[i]:
                    action_correct += 1

                # BarcodeType (2 pts each, 20 pts total)
                actual_type = row_lower.get("barcodetype", "").upper().replace(" ", "_").replace("-", "_")
                exp_type = expected_types[i] if i < len(expected_types) else ""
                if actual_type == exp_type:
                    type_correct += 1

                # GTIN (2 pts each for the 6 DataMatrix entries, 12 pts total)
                if i < len(expected_gtins) and expected_gtins[i]:
                    actual_gtin = row_lower.get("gtin", "").strip()
                    if actual_gtin == expected_gtins[i]:
                        gtin_correct += 1

            # award points
            num_datamatrix = sum(1 for g in expected_gtins if g)
            csv_score += int(round(15.0 * action_correct / max(n, 1)))
            csv_score += int(round(20.0 * type_correct / max(n, 1)))
            csv_score += int(round(12.0 * gtin_correct / max(num_datamatrix, 1)))

            # --- product name spot-check (8 pts) ---
            # Check a few key product name matches
            product_pts = 0
            product_checks = 0
            expected_products = {
                0: "lisinopril",
                2: "metformin",
                4: "omeprazole",
                6: "amoxicillin",
                9: "atorvastatin",
            }
            for idx, keyword in expected_products.items():
                if idx < len(rows):
                    row_lower = {k.strip().lower(): (v.strip().lower() if v else "") for k, v in rows[idx].items()}
                    pname = row_lower.get("productname", "")
                    product_checks += 1
                    if keyword in pname:
                        product_pts += 1

            if product_checks > 0:
                csv_score += int(round(8.0 * product_pts / product_checks))

            # --- existence bonus (5 pts) for having a non-trivial CSV ---
            if len(rows) >= 5:
                csv_score += 5

            details["action_accuracy"] = f"{action_correct}/{n}"
            details["type_accuracy"] = f"{type_correct}/{n}"
            details["gtin_accuracy"] = f"{gtin_correct}/{num_datamatrix}"
            details["product_accuracy"] = f"{product_pts}/{product_checks}"

    score += csv_score
    passed = score >= 55

    if not feedback:
        feedback.append("All checks passed")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": details,
        "subscores": {
            "ini_configuration": ini_score,
            "audit_report": csv_score,
        },
    }
