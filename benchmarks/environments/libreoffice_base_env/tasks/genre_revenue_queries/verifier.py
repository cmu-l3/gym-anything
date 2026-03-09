#!/usr/bin/env python3
"""
Verifier for genre_revenue_queries task.

Scoring breakdown (100 points total):
  - GenreRevenue query exists with joins + GROUP BY (25 pts)
  - CountryRevenue query exists with joins + GROUP BY (25 pts)
  - RevenueTarget table created (20 pts)
  - RevenueTarget has 4+ rows of data (15 pts)
  - Report containing 'revenue' in name created (15 pts)

Pass threshold: 70 points

Occupation context (top LibreOffice Base users by GDP):
  #1 Office Clerks, General: data entry into office databases
  #3 Secretaries & Administrative Assistants: contact lists / inventory databases
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
    """
    Pattern 8 (Anti-Tamper): Independently parse the ODB file.
    Returns parsed data without relying on the export JSON.
    """
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


def verify_genre_revenue_queries(traj, env_info, task_info):
    """Verify the genre revenue queries task completion."""
    copy_from_env = env_info.get('copy_from_env')

    score = 0
    feedback_parts = []

    # --- Step 1: Copy and parse exported result JSON ---
    tmp_json = None
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as f:
            tmp_json = f.name
        copy_from_env('/tmp/genre_revenue_queries_result.json', tmp_json)
        with open(tmp_json) as f:
            result = json.load(f)
    except Exception as e:
        logger.warning(f"Could not read export JSON: {e}")
    finally:
        if tmp_json and os.path.exists(tmp_json):
            os.unlink(tmp_json)

    # --- Step 2: Copy and check baseline initial state ---
    tmp_initial = None
    initial = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as f:
            tmp_initial = f.name
        copy_from_env('/tmp/genre_revenue_queries_initial.json', tmp_initial)
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
        logger.info(f"Independent ODB parse: queries={odb_parsed['query_names']}, "
                    f"new_tables={odb_parsed['new_table_names']}")
    except Exception as e:
        logger.warning(f"Independent ODB analysis failed: {e}")
    finally:
        if tmp_odb and os.path.exists(tmp_odb):
            os.unlink(tmp_odb)

    # Use independently-parsed ODB data if available, fall back to exported JSON
    authoritative = odb_parsed if odb_parsed.get("query_names") is not None else result

    if not authoritative and not result:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Could not retrieve task results from VM"
        }

    # Merge: prefer ODB-parsed for structural data, use JSON for any extra fields
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

    # Baseline comparison (Pattern 1): ensure new work done
    initial_new_tables = set(t.upper() for t in initial.get("new_table_names", []))
    initial_queries = set(q.lower() for q in initial.get("query_names", []))

    # --- Criterion 1: GenreRevenue query (25 pts) ---
    if "genrerevenue" in query_names_lower and "genrerevenue" not in initial_queries:
        cmd = query_commands.get("genrerevenue", "")
        has_join = "join" in cmd or ("invoiceline" in cmd and "track" in cmd)
        has_group = "group" in cmd
        has_aggregate = "sum(" in cmd or "count(" in cmd
        has_genre = "genre" in cmd
        if has_join and has_group and has_aggregate and has_genre:
            score += 25
            feedback_parts.append("GenreRevenue query correct (25pts)")
        else:
            score += 12
            feedback_parts.append(
                f"GenreRevenue query exists but incomplete "
                f"(join={has_join}, group={has_group}, agg={has_aggregate}) (12pts)"
            )
    else:
        feedback_parts.append("GenreRevenue query NOT found (0pts)")

    # --- Criterion 2: CountryRevenue query (25 pts) ---
    if "countryrevenue" in query_names_lower and "countryrevenue" not in initial_queries:
        cmd = query_commands.get("countryrevenue", "")
        has_join = "join" in cmd or ("invoice" in cmd and "customer" in cmd)
        has_group = "group" in cmd
        has_aggregate = "sum(" in cmd or "count(" in cmd
        has_country = "country" in cmd or "billing" in cmd
        if has_join and has_group and has_aggregate and has_country:
            score += 25
            feedback_parts.append("CountryRevenue query correct (25pts)")
        else:
            score += 12
            feedback_parts.append(
                f"CountryRevenue query exists but incomplete "
                f"(join={has_join}, group={has_group}, agg={has_aggregate}) (12pts)"
            )
    else:
        feedback_parts.append("CountryRevenue query NOT found (0pts)")

    # --- Criterion 3: RevenueTarget table (20 pts) ---
    if "REVENUETARGET" in new_tables_upper and "REVENUETARGET" not in initial_new_tables:
        score += 20
        feedback_parts.append("RevenueTarget table created (20pts)")
    else:
        feedback_parts.append("RevenueTarget table NOT found (0pts)")

    # --- Criterion 4: RevenueTarget data (15 pts) ---
    rt_count = insert_counts.get("REVENUETARGET", 0)
    if rt_count >= 4:
        score += 15
        feedback_parts.append(f"RevenueTarget has {rt_count} rows (15pts)")
    elif rt_count >= 1:
        score += 7
        feedback_parts.append(f"RevenueTarget has {rt_count} row(s), need 4+ (7pts partial)")
    else:
        feedback_parts.append("RevenueTarget has no data (0pts)")

    # --- Criterion 5: Revenue Analysis report (15 pts) ---
    if any("revenue" in r for r in report_names_lower):
        score += 15
        feedback_parts.append("Revenue report created (15pts)")
    else:
        feedback_parts.append("Revenue report NOT found (0pts)")

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
