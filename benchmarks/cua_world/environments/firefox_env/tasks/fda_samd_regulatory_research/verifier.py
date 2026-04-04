#!/usr/bin/env python3
"""Verifier for fda_samd_regulatory_research task.

Regulatory Affairs Manager task: Research FDA requirements for Software as a Medical Device
(SaMD) from FDA.gov, Federal Register, and IMDRF. Organize in bookmarks, download guidance
PDF, and produce a regulatory requirements matrix.

Scoring (100 points total, pass threshold 60):
- Criterion 1: FDA.gov visited ≥3 distinct pages (20 pts)
- Criterion 2: Federal Register and IMDRF visited (15 pts)
- Criterion 3: 'FDA Regulatory Research' bookmark folder with ≥6 bookmarks (20 pts)
- Criterion 4: Bookmarks span multiple sources (FDA + Federal Register or IMDRF) (10 pts)
- Criterion 5: PDF or guidance document downloaded (>10KB) (15 pts)
- Criterion 6: Regulatory matrix file exists and is fresh (10 pts)
- Criterion 7: Matrix content quality: SaMD + FDA + IMDRF + regulatory terms (10 pts)
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)


def verify_fda_samd_regulatory_research(traj, env_info, task_info):
    """Verify FDA SaMD regulatory research task completion."""

    copy_from_env = env_info.get('copy_from_env') or env_info.get('exec_capture')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/fda_samd_regulatory_research_result.json", tmp.name)
            with open(tmp.name, 'r', encoding='utf-8') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Could not read result file: {e}"}

    score = 0
    feedback_parts = []
    subscores = {}

    # GATE: No evidence of work
    no_evidence = (
        result.get('fda_visits', 0) == 0
        and not result.get('fda_bookmark_folder_exists', False)
        and not result.get('matrix_exists', False)
    )
    if no_evidence:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No evidence of work: FDA.gov not visited, no bookmarks, no matrix file"
        }

    # Criterion 1: FDA.gov visits (20 pts)
    fda_visits = result.get('fda_visits', 0)
    if fda_visits >= 5:
        score += 20
        subscores['fda_history'] = 20
        feedback_parts.append(f"FDA.gov visited {fda_visits} distinct pages (20/20)")
    elif fda_visits >= 3:
        score += 15
        subscores['fda_history'] = 15
        feedback_parts.append(f"FDA.gov visited {fda_visits} distinct pages (15/20)")
    elif fda_visits >= 1:
        score += 8
        subscores['fda_history'] = 8
        feedback_parts.append(f"FDA.gov visited {fda_visits} page(s) — need ≥3 distinct pages (8/20)")
    else:
        subscores['fda_history'] = 0
        feedback_parts.append("FDA.gov not visited (0/20)")

    # Criterion 2: Federal Register and IMDRF visits (15 pts)
    fedreg_visits = result.get('fedreg_visits', 0)
    imdrf_visits = result.get('imdrf_visits', 0)
    source_pts = 0
    if fedreg_visits >= 1:
        source_pts += 8
    if imdrf_visits >= 1:
        source_pts += 7
    score += source_pts
    subscores['multi_source_history'] = source_pts
    src_details = []
    if fedreg_visits >= 1:
        src_details.append(f"FedReg.gov ✓ ({fedreg_visits} pages)")
    else:
        src_details.append("FedReg.gov ✗ (not visited)")
    if imdrf_visits >= 1:
        src_details.append(f"IMDRF.org ✓ ({imdrf_visits} pages)")
    else:
        src_details.append("IMDRF.org ✗ (not visited)")
    feedback_parts.append(f"Multi-source coverage: {', '.join(src_details)} ({source_pts}/15)")

    # Criterion 3: FDA Regulatory Research bookmark folder with ≥6 bookmarks (20 pts)
    folder_exists = result.get('fda_bookmark_folder_exists', False)
    bm_count = result.get('fda_folder_bookmark_count', 0)
    if folder_exists and bm_count >= 6:
        score += 20
        subscores['bookmark_folder'] = 20
        feedback_parts.append(f"'FDA Regulatory Research' folder with {bm_count} bookmarks (20/20)")
    elif folder_exists and bm_count >= 3:
        pts = 12
        score += pts
        subscores['bookmark_folder'] = pts
        feedback_parts.append(f"'FDA Regulatory Research' folder with {bm_count} bookmarks (need ≥6) ({pts}/20)")
    elif folder_exists and bm_count >= 1:
        pts = 6
        score += pts
        subscores['bookmark_folder'] = pts
        feedback_parts.append(f"'FDA Regulatory Research' folder with only {bm_count} bookmark(s) ({pts}/20)")
    else:
        subscores['bookmark_folder'] = 0
        feedback_parts.append("'FDA Regulatory Research' bookmark folder not found (0/20)")

    # Criterion 4: Bookmarks span multiple sources (10 pts)
    fda_bm = result.get('fda_bookmarks_count', 0)
    fedreg_bm = result.get('fedreg_bookmarks_count', 0)
    imdrf_bm = result.get('imdrf_bookmarks_count', 0)
    unique_sources = sum([fda_bm >= 1, fedreg_bm >= 1, imdrf_bm >= 1])
    if unique_sources >= 3:
        score += 10
        subscores['bookmark_diversity'] = 10
        feedback_parts.append(f"Bookmarks span all 3 sources (FDA:{fda_bm}, FedReg:{fedreg_bm}, IMDRF:{imdrf_bm}) (10/10)")
    elif unique_sources == 2:
        score += 6
        subscores['bookmark_diversity'] = 6
        feedback_parts.append(f"Bookmarks span 2 sources (FDA:{fda_bm}, FedReg:{fedreg_bm}, IMDRF:{imdrf_bm}) (6/10)")
    elif unique_sources == 1:
        score += 2
        subscores['bookmark_diversity'] = 2
        feedback_parts.append(f"Bookmarks from only 1 source (2/10)")
    else:
        subscores['bookmark_diversity'] = 0
        feedback_parts.append("No bookmarks from required sources (0/10)")

    # Criterion 5: PDF or document downloaded (15 pts)
    pdf_downloads = result.get('pdf_downloads', 0)
    new_large_files = result.get('new_large_files', 0)
    if pdf_downloads >= 1:
        score += 15
        subscores['pdf_download'] = 15
        feedback_parts.append(f"{pdf_downloads} PDF(s) downloaded >10KB (15/15)")
    elif new_large_files >= 1:
        score += 8
        subscores['pdf_download'] = 8
        feedback_parts.append(f"Downloaded file(s) found but no PDF (8/15)")
    else:
        subscores['pdf_download'] = 0
        feedback_parts.append("No guidance documents downloaded (0/15)")

    # Criterion 6: Matrix file fresh (10 pts)
    if result.get('matrix_exists', False) and result.get('matrix_fresh', False):
        matrix_size = result.get('matrix_size', 0)
        if matrix_size >= 300:
            score += 10
            subscores['matrix_file'] = 10
            feedback_parts.append(f"Matrix file exists, fresh, {matrix_size} bytes (10/10)")
        else:
            score += 5
            subscores['matrix_file'] = 5
            feedback_parts.append(f"Matrix file exists but too short ({matrix_size} bytes) (5/10)")
    elif result.get('matrix_exists', False):
        subscores['matrix_file'] = 0
        feedback_parts.append("Matrix file predates task start (0/10)")
    else:
        subscores['matrix_file'] = 0
        feedback_parts.append("Matrix file ~/Documents/samd_regulatory_matrix.txt not found (0/10)")

    # Criterion 7: Matrix content quality (10 pts)
    content_score = 0
    keywords_found = []
    if result.get('matrix_has_samd', False):
        content_score += 3
        keywords_found.append("SaMD")
    if result.get('matrix_has_fda', False):
        content_score += 3
        keywords_found.append("FDA")
    if result.get('matrix_has_imdrf', False):
        content_score += 2
        keywords_found.append("IMDRF")
    if result.get('matrix_has_regulatory', False):
        content_score += 2
        keywords_found.append("regulatory terms")
    score += content_score
    subscores['matrix_content'] = content_score
    if keywords_found:
        feedback_parts.append(f"Matrix keywords: {', '.join(keywords_found)} ({content_score}/10)")
    else:
        feedback_parts.append("Matrix missing required keywords (0/10)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }
