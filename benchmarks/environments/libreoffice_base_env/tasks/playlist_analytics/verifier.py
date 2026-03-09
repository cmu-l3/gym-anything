#!/usr/bin/env python3
"""
Verifier for playlist_analytics task.

Scoring breakdown (100 points total):
  - PlaylistSummary query with correct joins + GROUP BY (25 pts)
  - TopArtistsInPlaylists query with Artist + PlaylistTrack joins (25 pts)
  - PlaylistTag table created (20 pts)
  - PlaylistTag has 5+ rows (15 pts)
  - Form containing 'Playlist' created (15 pts)

Pass threshold: 70 points

Occupation context: Library Technicians (#5 by GDP) — maintaining local specialized
inventories and querying backend data using desktop database tools.
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


def verify_playlist_analytics(traj, env_info, task_info):
    """Verify the playlist analytics task completion."""
    copy_from_env = env_info.get('copy_from_env')

    score = 0
    feedback_parts = []

    # --- Step 1: Copy and parse exported result JSON ---
    tmp_json = None
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as f:
            tmp_json = f.name
        copy_from_env('/tmp/playlist_analytics_result.json', tmp_json)
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
        copy_from_env('/tmp/playlist_analytics_initial.json', tmp_initial)
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
    form_names_lower = [f.lower() for f in (authoritative.get("form_names") or result.get("form_names", []))]
    insert_counts = {
        k.upper(): v for k, v in (authoritative.get("insert_counts") or result.get("insert_counts", {})).items()
    }

    initial_new_tables = {t.upper() for t in initial.get("new_table_names", [])}
    initial_queries = {q.lower() for q in initial.get("query_names", [])}

    # --- Criterion 1: PlaylistSummary query (25 pts) ---
    if "playlistsummary" in query_names_lower and "playlistsummary" not in initial_queries:
        cmd = query_commands.get("playlistsummary", "")
        has_playlist = "playlist" in cmd
        has_track = "track" in cmd
        has_join = "join" in cmd
        has_group = "group" in cmd
        has_aggregate = "sum(" in cmd or "count(" in cmd
        if has_playlist and has_track and has_join and has_group and has_aggregate:
            score += 25
            feedback_parts.append("PlaylistSummary query correct (25pts)")
        else:
            score += 12
            feedback_parts.append(
                f"PlaylistSummary exists but incomplete "
                f"(join={has_join}, group={has_group}, agg={has_aggregate}) (12pts)"
            )
    else:
        feedback_parts.append("PlaylistSummary query NOT found (0pts)")

    # --- Criterion 2: TopArtistsInPlaylists query (25 pts) ---
    if "topartistsinplaylists" in query_names_lower and "topartistsinplaylists" not in initial_queries:
        cmd = query_commands.get("topartistsinplaylists", "")
        has_artist = "artist" in cmd
        has_playlisttrack = "playlisttrack" in cmd or ("playlist" in cmd and "track" in cmd)
        has_group = "group" in cmd
        has_count = "count(" in cmd
        if has_artist and has_playlisttrack and has_group and has_count:
            score += 25
            feedback_parts.append("TopArtistsInPlaylists query correct (25pts)")
        else:
            score += 12
            feedback_parts.append(
                f"TopArtistsInPlaylists exists but incomplete "
                f"(artist={has_artist}, pltrack={has_playlisttrack}, group={has_group}) (12pts)"
            )
    else:
        feedback_parts.append("TopArtistsInPlaylists query NOT found (0pts)")

    # --- Criterion 3: PlaylistTag table (20 pts) ---
    if "PLAYLISTTAG" in new_tables_upper and "PLAYLISTTAG" not in initial_new_tables:
        score += 20
        feedback_parts.append("PlaylistTag table created (20pts)")
    else:
        feedback_parts.append("PlaylistTag table NOT found (0pts)")

    # --- Criterion 4: PlaylistTag data (15 pts) ---
    pt_count = insert_counts.get("PLAYLISTTAG", 0)
    if pt_count >= 5:
        score += 15
        feedback_parts.append(f"PlaylistTag has {pt_count} rows (15pts)")
    elif pt_count >= 2:
        score += 7
        feedback_parts.append(f"PlaylistTag has {pt_count} rows, need 5+ (7pts partial)")
    elif pt_count == 1:
        score += 3
        feedback_parts.append("PlaylistTag has 1 row, need 5+ (3pts partial)")
    else:
        feedback_parts.append("PlaylistTag has no data (0pts)")

    # --- Criterion 5: Playlist Tagger form (15 pts) ---
    if any("playlist" in f for f in form_names_lower):
        score += 15
        feedback_parts.append("Playlist form created (15pts)")
    else:
        feedback_parts.append("Playlist form NOT found (0pts)")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) if feedback_parts else "No subtasks completed",
        "details": {
            "query_names": list(query_names_lower),
            "new_table_names": list(new_tables_upper),
            "form_names": form_names_lower,
            "insert_counts": insert_counts,
            "odb_parse_ok": not bool(odb_parsed.get("error")),
        }
    }
