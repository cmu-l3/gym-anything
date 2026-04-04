#!/usr/bin/env python3
"""Verifier for editorial_review_pipeline task.

Checks that the agent completed the Q4 editorial review pipeline per the standards doc:
- dc:source, dc:rights, dc:language updated on documents that were missing them
- 'ready-for-review' tag applied to documents meeting all 3 metadata requirements
- 'needs-revision' tag applied to documents still missing metadata
- Editorial assessment Note created for each reviewed document
- Collection 'Q4 2025 Publications' created and populated with ready-for-review docs

Document states seeded by setup:
  Feature-Article-Climate-Change:    source='', rights='', language='' → needs-revision + update all
  Research-Report-AI-Ethics:         source=set, rights='', language='' → needs-revision + update rights/language
  Opinion-Column-Economic-Policy:    source=set, rights=set, language=set → ready-for-review (no changes needed)
  Breaking-News-Tech-Sector:         source='', rights='', language='' → needs-revision + update all

Scoring (100 pts total, pass at 60):
  dc:source set on 3+ docs (was missing):                 12 pts
  dc:rights set on 3+ docs (was missing):                 12 pts
  dc:language set on 3+ docs (was missing):               11 pts
  ready-for-review tag on Opinion-Column (already ready):  8 pts
  needs-revision tag on at least 2 incomplete docs:       10 pts
  ready-for-review on Feature or Research after update:    7 pts
  Editorial assessment notes created (>=3 docs):          20 pts
  Collection 'Q4 2025 Publications' exists:                5 pts
  Collection has ready-for-review docs (>=1):             15 pts
"""

import json

NUXEO_BASE = "http://localhost:8080/nuxeo/api/v1"
AUTH = "Administrator:Administrator"

DOCS = {
    "Feature-Article-Climate-Change":   "/default-domain/workspaces/Projects/Feature-Article-Climate-Change",
    "Research-Report-AI-Ethics":        "/default-domain/workspaces/Projects/Research-Report-AI-Ethics",
    "Opinion-Column-Economic-Policy":   "/default-domain/workspaces/Projects/Opinion-Column-Economic-Policy",
    "Breaking-News-Tech-Sector":        "/default-domain/workspaces/Projects/Breaking-News-Tech-Sector",
}

COLLECTION_TITLE = "Q4 2025 Publications"


def _api(exec_in_env, endpoint):
    cmd = f'curl -s -u {AUTH} -H "X-NXproperties: *" "{NUXEO_BASE}/{endpoint}"'
    raw = exec_in_env(cmd)
    try:
        return json.loads(raw)
    except Exception:
        return {}


def _get_doc(exec_in_env, path):
    return _api(exec_in_env, f"path{path}")


def _get_tags(exec_in_env, path):
    data = _api(exec_in_env, f"path{path}/@tagging")
    return [t.get("label", "").lower() for t in data.get("entries", [])]


def _find_collection(exec_in_env, title):
    safe = title.replace(" ", "+").replace("'", "%27")
    data = _api(exec_in_env,
                f"search/lang/NXQL/execute?query=SELECT+*+FROM+Collection+"
                f"WHERE+dc:title%3D%27{safe}%27+AND+ecm:isTrashed%3D0+AND+ecm:isVersion%3D0")
    entries = data.get("entries", [])
    return entries[0].get("uid", "") if entries else ""


def _collection_members(exec_in_env, coll_uid):
    data = _api(exec_in_env, f"id/{coll_uid}/contents?pageSize=20")
    return [e.get("title", "").lower() for e in data.get("entries", [])]


def _find_assessment_notes(exec_in_env):
    """Search Projects workspace for Note docs with 'assessment' in the title."""
    data = _api(exec_in_env,
                "search/lang/NXQL/execute?query=SELECT+*+FROM+Note+"
                "WHERE+ecm:path+STARTSWITH+%27/default-domain/workspaces/Projects%27+"
                "AND+dc:title+LIKE+%27%25Assessment%25%27+"
                "AND+ecm:isTrashed%3D0+AND+ecm:isVersion%3D0&pageSize=20")
    return data.get("entries", [])


def verify_editorial_review_pipeline(traj, env_info, task_info):
    exec_in_env = env_info.get("exec_in_env") or env_info.get("exec_capture")
    score = 0
    details = []

    try:
        # Collect doc data for reuse
        doc_data = {}
        doc_tags = {}
        for name, path in DOCS.items():
            doc_data[name] = _get_doc(exec_in_env, path)
            doc_tags[name] = _get_tags(exec_in_env, path)

        # -------------------------------------------------------
        # 1. dc:source set on docs that were missing it (12 pts)
        #    Feature and Breaking had empty source; check only those two
        # -------------------------------------------------------
        source_set_count = 0
        for name in ["Feature-Article-Climate-Change", "Breaking-News-Tech-Sector"]:
            props = doc_data[name].get("properties", {})
            val = (props.get("dc:source") or "").strip()
            if val:
                source_set_count += 1

        if source_set_count >= 2:
            score += 12
            details.append(f"PASS: dc:source set on both target docs (Feature + Breaking)")
        elif source_set_count == 1:
            score += 6
            details.append(f"PARTIAL: dc:source set on only {source_set_count}/2 target docs")
        else:
            details.append("FAIL: dc:source not set on Feature-Article or Breaking-News docs")

        # -------------------------------------------------------
        # 2. dc:rights set on docs that were missing it (12 pts)
        #    Feature, Research, Breaking all had empty rights; Opinion was set
        # -------------------------------------------------------
        rights_set_count = 0
        for name in ["Feature-Article-Climate-Change", "Research-Report-AI-Ethics",
                     "Breaking-News-Tech-Sector"]:
            props = doc_data[name].get("properties", {})
            val = (props.get("dc:rights") or "").strip()
            if val:
                rights_set_count += 1

        if rights_set_count >= 2:
            score += 12
            details.append(f"PASS: dc:rights set on {rights_set_count}/3 target docs")
        elif rights_set_count == 1:
            score += 6
            details.append(f"PARTIAL: dc:rights set on only {rights_set_count}/3 target docs")
        else:
            details.append("FAIL: dc:rights not set on any target docs")

        # -------------------------------------------------------
        # 3. dc:language set on docs that were missing it (11 pts)
        #    Feature, Research, Breaking all had empty language; Opinion was set
        # -------------------------------------------------------
        lang_set_count = 0
        for name in ["Feature-Article-Climate-Change", "Research-Report-AI-Ethics",
                     "Breaking-News-Tech-Sector"]:
            props = doc_data[name].get("properties", {})
            val = (props.get("dc:language") or "").strip()
            if val:
                lang_set_count += 1

        if lang_set_count >= 2:
            score += 11
            details.append(f"PASS: dc:language set on {lang_set_count}/3 target docs")
        elif lang_set_count == 1:
            score += 5
            details.append(f"PARTIAL: dc:language set on only {lang_set_count}/3 target docs")
        else:
            details.append("FAIL: dc:language not set on any target docs")

        # -------------------------------------------------------
        # 4. 'ready-for-review' tag on Opinion-Column (already complete, 8 pts)
        # -------------------------------------------------------
        opinion_tags = doc_tags["Opinion-Column-Economic-Policy"]
        if "ready-for-review" in opinion_tags:
            score += 8
            details.append("PASS: Opinion-Column correctly tagged 'ready-for-review'")
        else:
            details.append(f"FAIL: Opinion-Column not tagged 'ready-for-review' (tags={opinion_tags})")

        # -------------------------------------------------------
        # 5. 'needs-revision' tag on at least 2 incomplete docs (10 pts)
        #    Feature, Research, Breaking initially lacked metadata
        # -------------------------------------------------------
        needs_revision_count = 0
        for name in ["Feature-Article-Climate-Change", "Research-Report-AI-Ethics",
                     "Breaking-News-Tech-Sector"]:
            if "needs-revision" in doc_tags[name]:
                needs_revision_count += 1

        if needs_revision_count >= 2:
            score += 10
            details.append(f"PASS: {needs_revision_count} docs tagged 'needs-revision'")
        elif needs_revision_count == 1:
            score += 5
            details.append(f"PARTIAL: only {needs_revision_count} doc tagged 'needs-revision'")
        else:
            details.append("FAIL: no docs tagged 'needs-revision'")

        # -------------------------------------------------------
        # 6. 'ready-for-review' on docs that now have all 3 fields complete (7 pts)
        # -------------------------------------------------------
        newly_ready = 0
        for name in ["Feature-Article-Climate-Change", "Research-Report-AI-Ethics",
                     "Breaking-News-Tech-Sector"]:
            props = doc_data[name].get("properties", {})
            has_source = bool((props.get("dc:source") or "").strip())
            has_rights = bool((props.get("dc:rights") or "").strip())
            has_lang = bool((props.get("dc:language") or "").strip())
            if has_source and has_rights and has_lang and "ready-for-review" in doc_tags[name]:
                newly_ready += 1

        if newly_ready >= 1:
            score += 7
            details.append(f"PASS: {newly_ready} doc(s) fully updated and tagged 'ready-for-review'")
        else:
            details.append("FAIL: no docs updated to fully complete and tagged 'ready-for-review'")

        # -------------------------------------------------------
        # 7. Editorial assessment notes created for >= 3 docs (20 pts)
        # -------------------------------------------------------
        assessment_notes = _find_assessment_notes(exec_in_env)
        n_assessments = len(assessment_notes)
        if n_assessments >= 4:
            score += 20
            details.append(f"PASS: {n_assessments} editorial assessment notes created (all 4 docs)")
        elif n_assessments >= 3:
            score += 15
            details.append(f"PASS: {n_assessments} editorial assessment notes created")
        elif n_assessments >= 2:
            score += 10
            details.append(f"PARTIAL: {n_assessments} editorial assessment notes created (expected >=3)")
        elif n_assessments >= 1:
            score += 5
            details.append(f"PARTIAL: only {n_assessments} editorial assessment note created")
        else:
            details.append("FAIL: no editorial assessment notes found in Projects workspace")

        # -------------------------------------------------------
        # 8. Collection 'Q4 2025 Publications' exists (5 pts)
        # -------------------------------------------------------
        coll_uid = _find_collection(exec_in_env, COLLECTION_TITLE)
        if coll_uid:
            score += 5
            details.append(f"PASS: Collection '{COLLECTION_TITLE}' found")

            # -------------------------------------------------------
            # 9. Collection has at least one ready-for-review doc (15 pts)
            # -------------------------------------------------------
            members = _collection_members(exec_in_env, coll_uid)
            # At minimum Opinion-Column should be there; Feature, Research, Breaking if updated
            has_opinion = any("opinion" in m or "economic" in m or "monetary" in m for m in members)
            # Count any article in the collection
            article_count = sum(1 for m in members
                                if any(kw in m for kw in ["article", "feature", "research",
                                                            "opinion", "breaking", "climate",
                                                            "ethics", "economic", "tech"]))
            if article_count >= 2:
                score += 15
                details.append(f"PASS: Collection has {article_count} article(s) (members={members[:4]})")
            elif article_count >= 1 or has_opinion:
                score += 8
                details.append(f"PARTIAL: Collection has {article_count} article(s) (members={members[:4]})")
            else:
                details.append(f"FAIL: Collection exists but appears empty or has wrong docs (members={members[:4]})")
        else:
            details.append(f"FAIL: Collection '{COLLECTION_TITLE}' not found")

        # -------------------------------------------------------
        # Final result
        # -------------------------------------------------------
        passed = score >= 60
        feedback = f"Score: {score}/100. " + " | ".join(details)
        return {"passed": passed, "score": score, "feedback": feedback}

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
