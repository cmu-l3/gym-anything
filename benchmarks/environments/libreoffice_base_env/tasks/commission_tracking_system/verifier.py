#!/usr/bin/env python3
"""
Verifier for commission_tracking_system task.

Scoring breakdown (100 points total):
  - CommissionRate table created (20 pts)
  - Commission rates for EmployeeIds 3, 4, 5 all present (20 pts)
  - RepSalesTotal query with correct joins (25 pts)
  - CommissionDue query referencing commissions (20 pts)
  - Form containing 'Commission' created (15 pts)

Pass threshold: 70 points

Occupation context: Compensation, Benefits, and Job Analysis Specialists (#4 by GDP)
use LibreOffice Base to manage historical compensation data and run queries on
employee demographics not handled by standard HRIS reports.
"""
import json
import os
import re
import tempfile
import zipfile
import logging
import html as html_mod

logger = logging.getLogger(__name__)

ORIGINAL_TABLES_UPPER = {
    'MEDIATYPE', 'GENRE', 'ARTIST', 'EMPLOYEE', 'CUSTOMER',
    'ALBUM', 'TRACK', 'INVOICE', 'INVOICELINE', 'PLAYLIST', 'PLAYLISTTRACK'
}


def _parse_odb_independently(odb_path):
    """Pattern 8 (Anti-Tamper): Independently parse the ODB file."""
    parsed = {
        "query_names": [],
        "query_commands": {},
        "new_table_names": [],
        "form_names": [],
        "report_names": [],
        "insert_counts": {},
        "commission_rate_employee_ids": [],
        "error": None,
    }
    try:
        with zipfile.ZipFile(odb_path, 'r') as zf:
            members = zf.namelist()
            if "content.xml" in members:
                content = zf.read("content.xml").decode("utf-8", errors="replace")
                for m in re.finditer(
                    r'<db:query\b[^/]*?\bdb:name="([^"]+)"[^/]*?\bdb:command="([^"]*)"', content
                ):
                    name, cmd = m.group(1), html_mod.unescape(m.group(2))
                    if name not in parsed["query_names"]:
                        parsed["query_names"].append(name)
                    parsed["query_commands"][name] = cmd
                for m in re.finditer(
                    r'<db:query\b[^/]*?\bdb:command="([^"]*)"[^/]*?\bdb:name="([^"]+)"', content
                ):
                    cmd, name = html_mod.unescape(m.group(1)), m.group(2)
                    if name not in parsed["query_names"]:
                        parsed["query_names"].append(name)
                        parsed["query_commands"][name] = cmd
                forms_m = re.search(r'<db:forms\b[^>]*>(.*?)</db:forms>', content, re.DOTALL)
                if forms_m:
                    parsed["form_names"] = re.findall(r'\bdb:name="([^"]+)"', forms_m.group(1))
                reports_m = re.search(r'<db:reports\b[^>]*>(.*?)</db:reports>', content, re.DOTALL)
                if reports_m:
                    parsed["report_names"] = re.findall(r'\bdb:name="([^"]+)"', reports_m.group(1))
            if not parsed["form_names"]:
                form_dirs = set()
                for member in members:
                    parts = member.split('/')
                    if len(parts) >= 2 and parts[0] == 'forms' and parts[1]:
                        form_dirs.add(parts[1])
                parsed["form_names"] = list(form_dirs)
            if not parsed["report_names"]:
                report_dirs = set()
                for member in members:
                    parts = member.split('/')
                    if len(parts) >= 2 and parts[0] == 'reports' and parts[1]:
                        report_dirs.add(parts[1])
                parsed["report_names"] = list(report_dirs)
            if "database/script" in members:
                script = zf.read("database/script").decode("utf-8", errors="replace")
                tables = re.findall(
                    r'CREATE (?:CACHED )?TABLE (?:PUBLIC\.)?"?([^"(\s]+)"?\s*\(',
                    script, re.IGNORECASE
                )
                tables = [t.strip().strip('"') for t in tables]
                parsed["new_table_names"] = [t for t in tables if t.upper() not in ORIGINAL_TABLES_UPPER]
                for tname in parsed["new_table_names"]:
                    pattern = rf'INSERT INTO (?:PUBLIC\.)?"{re.escape(tname)}"'
                    count = len(re.findall(pattern, script, re.IGNORECASE))
                    parsed["insert_counts"][tname] = count
                # Extract CommissionRate employee IDs
                cr_inserts = re.findall(
                    r'INSERT INTO (?:PUBLIC\.)?(?:"COMMISSIONRATE"|"CommissionRate"|COMMISSIONRATE)\s+VALUES\s*\(([^)]+)\)',
                    script, re.IGNORECASE
                )
                emp_ids = []
                for ins in cr_inserts:
                    parts = [p.strip().strip("'\"") for p in ins.split(',')]
                    if len(parts) >= 2:
                        try:
                            emp_ids.append(int(parts[1]))
                        except (ValueError, IndexError):
                            pass
                parsed["commission_rate_employee_ids"] = list(set(emp_ids))
    except Exception as e:
        parsed["error"] = str(e)
        logger.warning(f"Independent ODB parse failed: {e}")
    return parsed


def verify_commission_tracking_system(traj, env_info, task_info):
    """Verify the commission tracking system task completion."""
    copy_from_env = env_info.get('copy_from_env')

    score = 0
    feedback_parts = []

    # --- Step 1: Copy and parse exported result JSON ---
    tmp_json = None
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as f:
            tmp_json = f.name
        copy_from_env('/tmp/commission_tracking_system_result.json', tmp_json)
        with open(tmp_json) as f:
            result = json.load(f)
    except Exception as e:
        logger.warning(f"Could not read export JSON: {e}")
    finally:
        if tmp_json and os.path.exists(tmp_json):
            os.unlink(tmp_json)

    # --- Step 2: Copy baseline initial state ---
    tmp_initial = None
    initial = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as f:
            tmp_initial = f.name
        copy_from_env('/tmp/commission_tracking_system_initial.json', tmp_initial)
        with open(tmp_initial) as f:
            initial = json.load(f)
    except Exception as e:
        logger.warning(f"Could not read initial baseline: {e}")
    finally:
        if tmp_initial and os.path.exists(tmp_initial):
            os.unlink(tmp_initial)

    # --- Step 3: Pattern 8 - Independently re-parse ODB (anti-tamper) ---
    tmp_odb = None
    odb_parsed = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.odb', delete=False) as f:
            tmp_odb = f.name
        copy_from_env('/home/ga/chinook.odb', tmp_odb)
        odb_parsed = _parse_odb_independently(tmp_odb)
    except Exception as e:
        logger.warning(f"Independent ODB analysis failed: {e}")
    finally:
        if tmp_odb and os.path.exists(tmp_odb):
            os.unlink(tmp_odb)

    # Use independently-parsed ODB data as authoritative, fall back to exported JSON
    authoritative = odb_parsed if odb_parsed.get("query_names") is not None else result
    if not authoritative and not result:
        return {"passed": False, "score": 0, "feedback": "Could not retrieve task results from VM"}

    query_names_lower = {q.lower() for q in (authoritative.get("query_names") or result.get("query_names", []))}
    query_commands = {
        k.lower(): html_mod.unescape(v).lower()
        for k, v in (authoritative.get("query_commands") or result.get("query_commands", {})).items()
    }
    new_tables_upper = {t.upper() for t in (authoritative.get("new_table_names") or result.get("new_table_names", []))}
    form_names_lower = [f.lower() for f in (authoritative.get("form_names") or result.get("form_names", []))]
    insert_counts = {
        k.upper(): v for k, v in (authoritative.get("insert_counts") or result.get("insert_counts", {})).items()
    }
    # Prefer ODB-parsed employee IDs, fall back to export JSON
    emp_ids_found = set(
        odb_parsed.get("commission_rate_employee_ids") or result.get("commission_rate_employee_ids", [])
    )

    initial_new_tables = {t.upper() for t in initial.get("new_table_names", [])}
    initial_queries = {q.lower() for q in initial.get("query_names", [])}

    # --- Criterion 1: CommissionRate table (20 pts) ---
    if "COMMISSIONRATE" in new_tables_upper and "COMMISSIONRATE" not in initial_new_tables:
        score += 20
        feedback_parts.append("CommissionRate table created (20pts)")
    else:
        feedback_parts.append("CommissionRate table NOT found (0pts)")

    # --- Criterion 2: Rates for employees 3, 4, 5 (20 pts) ---
    required_emp_ids = {3, 4, 5}
    found_required = required_emp_ids & emp_ids_found
    if found_required == required_emp_ids:
        score += 20
        feedback_parts.append("Commission rates for all 3 reps (EmpIds 3,4,5) present (20pts)")
    elif len(found_required) >= 2:
        score += 12
        feedback_parts.append(f"Rates for {len(found_required)}/3 reps found (12pts partial)")
    elif len(found_required) == 1:
        score += 5
        feedback_parts.append("Rate for 1/3 reps found (5pts partial)")
    else:
        cr_count = insert_counts.get("COMMISSIONRATE", 0)
        if cr_count >= 3:
            score += 10
            feedback_parts.append(f"CommissionRate has {cr_count} rows but emp IDs unclear (10pts)")
        else:
            feedback_parts.append("No commission rate data for required employees (0pts)")

    # --- Criterion 3: RepSalesTotal query (25 pts) ---
    if "repsalestotal" in query_names_lower and "repsalestotal" not in initial_queries:
        cmd = query_commands.get("repsalestotal", "")
        has_employee = "employee" in cmd
        has_invoice = "invoice" in cmd
        has_group = "group" in cmd
        has_join = "join" in cmd or ("customer" in cmd and "employee" in cmd)
        if has_employee and has_invoice and has_group and has_join:
            score += 25
            feedback_parts.append("RepSalesTotal query correct (25pts)")
        else:
            score += 12
            feedback_parts.append(
                f"RepSalesTotal exists but incomplete "
                f"(emp={has_employee}, inv={has_invoice}, group={has_group}) (12pts)"
            )
    else:
        feedback_parts.append("RepSalesTotal query NOT found (0pts)")

    # --- Criterion 4: CommissionDue query (20 pts) ---
    if "commissiondue" in query_names_lower and "commissiondue" not in initial_queries:
        cmd = query_commands.get("commissiondue", "")
        has_commission = "commission" in cmd or "commissionpct" in cmd or "commissionrate" in cmd
        has_employee = "employee" in cmd or "repname" in cmd or "repsalestotal" in cmd
        if has_commission and has_employee:
            score += 20
            feedback_parts.append("CommissionDue query correct (20pts)")
        else:
            score += 10
            feedback_parts.append(
                f"CommissionDue exists but incomplete "
                f"(commission={has_commission}, emp={has_employee}) (10pts)"
            )
    else:
        feedback_parts.append("CommissionDue query NOT found (0pts)")

    # --- Criterion 5: Commission Entry form (15 pts) ---
    if any("commission" in f for f in form_names_lower):
        score += 15
        feedback_parts.append("Commission form created (15pts)")
    else:
        feedback_parts.append("Commission form NOT found (0pts)")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) if feedback_parts else "No subtasks completed",
        "details": {
            "query_names": list(query_names_lower),
            "new_table_names": list(new_tables_upper),
            "form_names": form_names_lower,
            "commission_employee_ids": list(emp_ids_found),
            "insert_counts": insert_counts,
            "odb_parse_ok": not bool(odb_parsed.get("error")),
        }
    }
