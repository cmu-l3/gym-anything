#!/usr/bin/env python3
"""
Verifier for customer_segmentation task.

Scoring breakdown (100 points total):
  - CustomerLifetimeValue query with correct joins + aggregates (25 pts)
  - CustomerTier table created (20 pts)
  - CustomerTier has 4+ rows (15 pts)
  - CustomerTierAssignment query exists and references tier/spend (25 pts)
  - Report containing 'Customer' created (15 pts)

Pass threshold: 70 points

Occupation context: Office Clerks, General (#1 by GDP) — data entry into office
databases for records management. Secretaries (#3) — contact lists/inventory DBs.
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
    except Exception as e:
        parsed["error"] = str(e)
        logger.warning(f"Independent ODB parse failed: {e}")
    return parsed


def verify_customer_segmentation(traj, env_info, task_info):
    """Verify the customer segmentation task completion."""
    copy_from_env = env_info.get('copy_from_env')

    score = 0
    feedback_parts = []

    # --- Step 1: Copy and parse exported result JSON ---
    tmp_json = None
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as f:
            tmp_json = f.name
        copy_from_env('/tmp/customer_segmentation_result.json', tmp_json)
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
        copy_from_env('/tmp/customer_segmentation_initial.json', tmp_initial)
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

    authoritative = odb_parsed if odb_parsed.get("query_names") is not None else result
    if not authoritative and not result:
        return {"passed": False, "score": 0, "feedback": "Could not retrieve task results from VM"}

    query_names_lower = {q.lower() for q in (authoritative.get("query_names") or result.get("query_names", []))}
    query_commands = {
        k.lower(): html_mod.unescape(v).lower()
        for k, v in (authoritative.get("query_commands") or result.get("query_commands", {})).items()
    }
    new_tables_upper = {t.upper() for t in (authoritative.get("new_table_names") or result.get("new_table_names", []))}
    report_names_lower = [r.lower() for r in (authoritative.get("report_names") or result.get("report_names", []))]
    insert_counts = {
        k.upper(): v for k, v in (authoritative.get("insert_counts") or result.get("insert_counts", {})).items()
    }

    initial_new_tables = {t.upper() for t in initial.get("new_table_names", [])}
    initial_queries = {q.lower() for q in initial.get("query_names", [])}

    # --- Criterion 1: CustomerLifetimeValue query (25 pts) ---
    if "customerlifetimevalue" in query_names_lower and "customerlifetimevalue" not in initial_queries:
        cmd = query_commands.get("customerlifetimevalue", "")
        has_customer = "customer" in cmd
        has_invoice = "invoice" in cmd
        has_join = "join" in cmd
        has_group = "group" in cmd
        has_aggregate = "sum(" in cmd or "count(" in cmd or "avg(" in cmd
        if has_customer and has_invoice and has_join and has_group and has_aggregate:
            score += 25
            feedback_parts.append("CustomerLifetimeValue query correct (25pts)")
        else:
            score += 12
            feedback_parts.append(
                f"CustomerLifetimeValue exists but incomplete "
                f"(join={has_join}, group={has_group}, agg={has_aggregate}) (12pts)"
            )
    else:
        feedback_parts.append("CustomerLifetimeValue query NOT found (0pts)")

    # --- Criterion 2: CustomerTier table (20 pts) ---
    if "CUSTOMERTIER" in new_tables_upper and "CUSTOMERTIER" not in initial_new_tables:
        score += 20
        feedback_parts.append("CustomerTier table created (20pts)")
    else:
        feedback_parts.append("CustomerTier table NOT found (0pts)")

    # --- Criterion 3: CustomerTier data (15 pts) ---
    ct_count = insert_counts.get("CUSTOMERTIER", 0)
    if ct_count >= 4:
        score += 15
        feedback_parts.append(f"CustomerTier has {ct_count} rows (15pts)")
    elif ct_count >= 2:
        score += 8
        feedback_parts.append(f"CustomerTier has {ct_count} rows, need 4+ (8pts partial)")
    elif ct_count == 1:
        score += 3
        feedback_parts.append("CustomerTier has 1 row, need 4+ (3pts partial)")
    else:
        feedback_parts.append("CustomerTier has no data (0pts)")

    # --- Criterion 4: CustomerTierAssignment query (25 pts) ---
    if "customertierassignment" in query_names_lower and "customertierassignment" not in initial_queries:
        cmd = query_commands.get("customertierassignment", "")
        has_customer = "customer" in cmd
        has_tier = "tier" in cmd or "customertier" in cmd
        if has_customer and has_tier:
            score += 25
            feedback_parts.append("CustomerTierAssignment query correct (25pts)")
        else:
            score += 12
            feedback_parts.append(
                f"CustomerTierAssignment exists but incomplete "
                f"(customer={has_customer}, tier={has_tier}) (12pts)"
            )
    else:
        feedback_parts.append("CustomerTierAssignment query NOT found (0pts)")

    # --- Criterion 5: Customer Analysis report (15 pts) ---
    if any("customer" in r for r in report_names_lower):
        score += 15
        feedback_parts.append("Customer Analysis report created (15pts)")
    else:
        feedback_parts.append("Customer Analysis report NOT found (0pts)")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) if feedback_parts else "No subtasks completed",
        "details": {
            "query_names": list(query_names_lower),
            "new_table_names": list(new_tables_upper),
            "report_names": report_names_lower,
            "insert_counts": insert_counts,
            "odb_parse_ok": not bool(odb_parsed.get("error")),
        }
    }
