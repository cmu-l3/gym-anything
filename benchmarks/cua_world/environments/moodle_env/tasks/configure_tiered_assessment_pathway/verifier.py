#!/usr/bin/env python3
"""Verifier for Configure Tiered Assessment Pathway task in Moodle.

This is a stub verifier. The primary evaluation will be done by
vlm_checklist_verifier. This verifier performs basic programmatic checks
on the exported JSON result to provide a rough score.

Criteria (100 points total):
  1. Quiz exists + settings correct      (20 pts)
  2. Page exists + completion             ( 8 pts)
  3. Assignment exists + settings         (12 pts)
  4. Assignment restrict access           (15 pts)
  5. Forum exists + settings              (12 pts)
  6. Forum restrict access                (10 pts)
  7. Gradebook structure                  (13 pts)
  8. Course completion                    ( 5 pts)
  9. Anti-gaming timestamp                ( 5 pts)

Pass threshold: 50 pts
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_tiered_assessment_pathway(traj, env_info, task_info):
    """Verify the tiered assessment pathway is correctly configured."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/tiered_assessment_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                r = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        fb = []

        # =====================================================================
        # 1. Quiz — Drug Classification Exam (20 pts)
        # =====================================================================
        if r.get('quiz_found'):
            score += 5
            fb.append("Quiz found")

            # Time limit: 1800s (30 min)
            tl = int(r.get('quiz_timelimit', 0))
            if 1700 <= tl <= 1900:
                score += 3
                fb.append(f"Quiz timelimit OK ({tl}s)")
            else:
                fb.append(f"Quiz timelimit wrong ({tl}s, expected ~1800)")

            # Max attempts: 2
            att = int(r.get('quiz_attempts', 0))
            if att == 2:
                score += 2
                fb.append("Quiz attempts=2 OK")
            else:
                fb.append(f"Quiz attempts wrong ({att}, expected 2)")

            # Grade-to-pass: 75
            gp = float(r.get('quiz_gradepass', 0))
            if 70 <= gp <= 80:
                score += 3
                fb.append(f"Quiz gradepass OK ({gp})")
            else:
                fb.append(f"Quiz gradepass wrong ({gp}, expected ~75)")

            # Completion: require passing grade (completion=2, completionpassgrade=1)
            qcomp = int(r.get('quiz_completion', 0))
            qcpg = int(r.get('quiz_completionpassgrade', 0))
            if qcomp == 2 and qcpg == 1:
                score += 4
                fb.append("Quiz completion=passgrade OK")
            elif qcomp == 2:
                score += 2
                fb.append("Quiz completion automatic but passgrade not set")
            else:
                fb.append(f"Quiz completion wrong (comp={qcomp}, passgrade={qcpg})")

            # Questions added
            slots = int(r.get('quiz_slot_count', 0))
            if slots >= 5:
                score += 3
                fb.append(f"Quiz has {slots} questions")
            elif slots >= 1:
                score += 1
                fb.append(f"Quiz has only {slots} questions (expected >=5)")
            else:
                fb.append("Quiz has no questions")
        else:
            fb.append("Quiz NOT found")

        # =====================================================================
        # 2. Page — Pharmacokinetics Reading (8 pts)
        # =====================================================================
        if r.get('page_found'):
            score += 4
            fb.append("Page found")

            pcomp = int(r.get('page_completion', 0))
            pcv = int(r.get('page_completionview', 0))
            if pcomp == 2 and pcv == 1:
                score += 4
                fb.append("Page view-completion OK")
            elif pcomp == 2:
                score += 2
                fb.append("Page automatic completion but completionview not set")
            else:
                fb.append(f"Page completion wrong (comp={pcomp}, view={pcv})")
        else:
            fb.append("Page NOT found")

        # =====================================================================
        # 3. Assignment — Medication Safety Case Study (12 pts)
        # =====================================================================
        if r.get('assign_found'):
            score += 4
            fb.append("Assignment found")

            # Grade max: 100
            ag = float(r.get('assign_grade', 0))
            if 95 <= ag <= 105:
                score += 2
                fb.append(f"Assignment grade={ag} OK")
            else:
                fb.append(f"Assignment grade wrong ({ag}, expected 100)")

            # Grade-to-pass: 60
            agp = float(r.get('assign_gradepass', 0))
            if 55 <= agp <= 65:
                score += 2
                fb.append(f"Assignment gradepass={agp} OK")
            else:
                fb.append(f"Assignment gradepass wrong ({agp}, expected 60)")

            # Completion: require submission
            acomp = int(r.get('assign_completion', 0))
            acsub = int(r.get('assign_completionsubmit', 0))
            if acomp == 2 and acsub == 1:
                score += 4
                fb.append("Assignment completion=submit OK")
            elif acomp == 2:
                score += 2
                fb.append("Assignment automatic completion but submit not set")
            else:
                fb.append(f"Assignment completion wrong (comp={acomp}, submit={acsub})")
        else:
            fb.append("Assignment NOT found")

        # =====================================================================
        # 4. Assignment restrict access (15 pts)
        # =====================================================================
        avail = r.get('assign_availability', '') or ''
        quiz_cmid = str(r.get('quiz_cmid', 0))
        page_cmid = str(r.get('page_cmid', 0))

        # Check quiz completion restriction
        if quiz_cmid != '0' and quiz_cmid in avail and 'completion' in avail:
            score += 8
            fb.append("Assignment restricted by quiz completion")
        else:
            fb.append("Assignment restriction by quiz MISSING")

        # Check page completion restriction
        if page_cmid != '0' and page_cmid in avail and 'completion' in avail:
            score += 7
            fb.append("Assignment restricted by page completion")
        else:
            fb.append("Assignment restriction by page MISSING")

        # =====================================================================
        # 5. Forum — Clinical Drug Interaction Analysis (12 pts)
        # =====================================================================
        if r.get('forum_found'):
            score += 3
            fb.append("Forum found")

            # Q&A type
            ftype = r.get('forum_type', '')
            if ftype == 'qanda':
                score += 2
                fb.append("Forum type=Q&A OK")
            else:
                fb.append(f"Forum type wrong ('{ftype}', expected 'qanda')")

            # Rating: assessed=1 (Average), scale=5
            fassessed = int(r.get('forum_assessed', 0))
            fscale = int(r.get('forum_scale', 0))
            if fassessed == 1 and fscale == 5:
                score += 3
                fb.append("Forum rating OK (avg, scale=5)")
            elif fassessed > 0:
                score += 1
                fb.append(f"Forum rating partially correct (assessed={fassessed}, scale={fscale})")
            else:
                fb.append("Forum rating NOT configured")

            # Completion: require post
            fcomp = int(r.get('forum_completion', 0))
            fposts = int(r.get('forum_completionposts', 0))
            fdisc = int(r.get('forum_completiondiscussions', 0))
            if fcomp == 2 and (fposts >= 1 or fdisc >= 1):
                score += 4
                fb.append("Forum post-completion OK")
            elif fcomp == 2:
                score += 2
                fb.append("Forum automatic completion but post requirement not set")
            else:
                fb.append(f"Forum completion wrong (comp={fcomp}, posts={fposts})")
        else:
            fb.append("Forum NOT found")

        # =====================================================================
        # 6. Forum restrict access (10 pts)
        # =====================================================================
        forum_avail = r.get('forum_availability', '') or ''
        assign_cmid = str(r.get('assign_cmid', 0))

        # The forum should be restricted by the assignment's grade.
        # This can appear as either 'grade' type or 'completion' type.
        if assign_cmid != '0' and assign_cmid in forum_avail:
            if 'grade' in forum_avail:
                score += 10
                fb.append("Forum restricted by assignment grade")
            elif 'completion' in forum_avail:
                score += 7
                fb.append("Forum restricted by assignment completion (expected grade)")
            else:
                score += 3
                fb.append("Forum references assignment but restriction type unclear")
        else:
            fb.append("Forum restriction by assignment MISSING")

        # =====================================================================
        # 7. Gradebook structure (13 pts)
        # =====================================================================
        agg = int(r.get('gradebook_aggregation', 0))
        if agg == 10:
            score += 4
            fb.append("Gradebook weighted mean OK")
        elif agg == 11:
            score += 2
            fb.append("Gradebook simple weighted mean (expected weighted mean of grades)")
        else:
            fb.append(f"Gradebook aggregation wrong ({agg}, expected 10)")

        # Category checks (3 pts each = 9 pts)
        for cat_name, cat_key, expected in [
            ('Foundation', 'foundation', 25),
            ('Application', 'application', 35),
            ('Synthesis', 'synthesis', 40),
        ]:
            found = r.get(f'{cat_key}_cat_found', False)
            weight = float(r.get(f'{cat_key}_cat_weight', 0))
            if found:
                score += 1
                # Weight can be stored as decimal (0.25) or percentage (25.0)
                if abs(weight - expected) < 8 or abs(weight - expected / 100.0) < 0.08:
                    score += 2
                    fb.append(f"{cat_name} category found, weight OK ({weight})")
                else:
                    fb.append(f"{cat_name} category found but weight wrong ({weight}, expected ~{expected})")
            else:
                fb.append(f"{cat_name} category NOT found")

        # =====================================================================
        # 8. Course completion (5 pts)
        # =====================================================================
        cc_count = int(r.get('course_completion_criteria_count', 0))
        if cc_count >= 3:
            score += 5
            fb.append(f"Course completion configured ({cc_count} criteria)")
        elif cc_count >= 1:
            score += 2
            fb.append(f"Course completion partial ({cc_count} criteria, expected >=3)")
        else:
            fb.append("Course completion NOT configured")

        # =====================================================================
        # 9. Anti-gaming timestamp (5 pts)
        # =====================================================================
        # At least the quiz should have been created during the task session
        if r.get('quiz_found') and int(r.get('quiz_id', 0)) > 0:
            score += 5
        else:
            fb.append("No activities appear created during task session")

        passed = score >= 50

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(fb)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
