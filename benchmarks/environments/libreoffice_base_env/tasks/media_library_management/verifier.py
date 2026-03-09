#!/usr/bin/env python3
"""
Verifier for media_library_management task.

Scoring breakdown (100 points total):
  - FullTrackCatalog query with 5-table joins (25 pts)
  - GenreMediaBreakdown query with GROUP BY genre+mediatype (20 pts)
  - TrackReview table created (20 pts)
  - TrackReview has 5+ rows with valid ratings 1-5 (20 pts)
  - Report containing 'Catalog' or 'Media' created (15 pts)

Pass threshold: 70 points

Occupation context: Library Technicians (#5 by GDP) — maintaining local specialized
inventories, querying backend data, and reference management databases.
Library Science Teachers (#7) — teaching information retrieval and SQL fundamentals.
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
        "track_review_ratings": [],
        "track_review_track_ids": [],
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
                # Extract TrackReview data
                tr_inserts = re.findall(
                    r'INSERT INTO (?:PUBLIC\.)?(?:"TrackReview"|"TRACKREVIEW"|TRACKREVIEW)\s+VALUES\s*\(([^)]+)\)',
                    script, re.IGNORECASE
                )
                ratings = []
                track_ids = []
                for ins in tr_inserts:
                    parts = [p.strip().strip("'\"") for p in ins.split(',')]
                    if len(parts) >= 3:
                        try:
                            track_ids.append(int(parts[1]))
                            ratings.append(int(parts[2]))
                        except (ValueError, IndexError):
                            pass
                parsed["track_review_ratings"] = ratings
                parsed["track_review_track_ids"] = track_ids
    except Exception as e:
        parsed["error"] = str(e)
        logger.warning(f"Independent ODB parse failed: {e}")
    return parsed


def verify_media_library_management(traj, env_info, task_info):
    """Verify the media library management task completion."""
    copy_from_env = env_info.get('copy_from_env')

    score = 0
    feedback_parts = []

    # --- Step 1: Copy and parse exported result JSON ---
    tmp_json = None
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as f:
            tmp_json = f.name
        copy_from_env('/tmp/media_library_management_result.json', tmp_json)
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
        copy_from_env('/tmp/media_library_management_initial.json', tmp_initial)
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
    ratings = odb_parsed.get("track_review_ratings") or result.get("track_review_ratings", [])
    track_ids = odb_parsed.get("track_review_track_ids") or result.get("track_review_track_ids", [])

    initial_new_tables = {t.upper() for t in initial.get("new_table_names", [])}
    initial_queries = {q.lower() for q in initial.get("query_names", [])}

    # --- Criterion 1: FullTrackCatalog query (25 pts) ---
    if "fulltrackcatalog" in query_names_lower and "fulltrackcatalog" not in initial_queries:
        cmd = query_commands.get("fulltrackcatalog", "")
        has_track = "track" in cmd
        has_album = "album" in cmd
        has_artist = "artist" in cmd
        has_genre = "genre" in cmd
        has_mediatype = "mediatype" in cmd or "media" in cmd
        join_count = cmd.count("join")
        tables_covered = sum([has_track, has_album, has_artist, has_genre, has_mediatype])
        if tables_covered >= 5 and join_count >= 4:
            score += 25
            feedback_parts.append("FullTrackCatalog 5-table join query correct (25pts)")
        elif tables_covered >= 4 and join_count >= 3:
            score += 15
            feedback_parts.append(
                f"FullTrackCatalog: {tables_covered}/5 tables, {join_count} joins (15pts)"
            )
        elif tables_covered >= 3:
            score += 8
            feedback_parts.append(
                f"FullTrackCatalog only {tables_covered}/5 tables (8pts)"
            )
        else:
            score += 5
            feedback_parts.append("FullTrackCatalog exists but incomplete (5pts)")
    else:
        feedback_parts.append("FullTrackCatalog query NOT found (0pts)")

    # --- Criterion 2: GenreMediaBreakdown query (20 pts) ---
    if "genremediabreakdown" in query_names_lower and "genremediabreakdown" not in initial_queries:
        cmd = query_commands.get("genremediabreakdown", "")
        has_genre = "genre" in cmd
        has_mediatype = "mediatype" in cmd or "media" in cmd
        has_group = "group" in cmd
        has_aggregate = "sum(" in cmd or "count(" in cmd
        if has_genre and has_mediatype and has_group and has_aggregate:
            score += 20
            feedback_parts.append("GenreMediaBreakdown query correct (20pts)")
        else:
            score += 10
            feedback_parts.append(
                f"GenreMediaBreakdown exists but incomplete "
                f"(genre={has_genre}, media={has_mediatype}, group={has_group}) (10pts)"
            )
    else:
        feedback_parts.append("GenreMediaBreakdown query NOT found (0pts)")

    # --- Criterion 3: TrackReview table (20 pts) ---
    if "TRACKREVIEW" in new_tables_upper and "TRACKREVIEW" not in initial_new_tables:
        score += 20
        feedback_parts.append("TrackReview table created (20pts)")
    else:
        feedback_parts.append("TrackReview table NOT found (0pts)")

    # --- Criterion 4: TrackReview data (20 pts) ---
    tr_count = insert_counts.get("TRACKREVIEW", 0)
    valid_ratings = [r for r in ratings if 1 <= r <= 5]
    valid_track_ids = [t for t in track_ids if 1 <= t <= 3503]

    if tr_count >= 5:
        if len(valid_ratings) >= 3:
            score += 20
            feedback_parts.append(f"TrackReview has {tr_count} rows with valid ratings (20pts)")
        else:
            score += 12
            feedback_parts.append(f"TrackReview has {tr_count} rows, rating validation unclear (12pts)")
    elif tr_count >= 3:
        score += 12
        feedback_parts.append(f"TrackReview has {tr_count} rows, need 5+ (12pts partial)")
    elif tr_count >= 1:
        score += 6
        feedback_parts.append(f"TrackReview has {tr_count} row(s), need 5+ (6pts partial)")
    else:
        feedback_parts.append("TrackReview has no data (0pts)")

    # --- Criterion 5: Media Catalog report (15 pts) ---
    if any("catalog" in r or "media" in r for r in report_names_lower):
        score += 15
        feedback_parts.append("Media/Catalog report created (15pts)")
    else:
        feedback_parts.append("Media/Catalog report NOT found (0pts)")

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
            "track_review_row_count": tr_count,
            "ratings_found": ratings,
            "odb_parse_ok": not bool(odb_parsed.get("error")),
        }
    }
