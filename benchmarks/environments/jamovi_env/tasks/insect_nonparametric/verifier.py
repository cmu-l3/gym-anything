#!/usr/bin/env python3
"""
Verifier for insect_nonparametric task (jamovi InsectSprays dataset).

Scoring (100 points total):
  Criterion 1 (15 pts): File saved at the correct path
  Criterion 2 (10 pts): Valid .omv structure (ZIP with expected contents)
  Criterion 3 (20 pts): Descriptives present with count split by spray
  Criterion 4 (15 pts): Normality test (Shapiro-Wilk) present
  Criterion 5 (25 pts): Kruskal-Wallis test present with correct variables
  Criterion 6 (15 pts): Pairwise comparisons present

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_insect_nonparametric(traj, env_info, task_info):
    """Verify the insect sprays non-parametric analysis task."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback = []

    # ------------------------------------------------------------------
    # Load the task result JSON produced by export_result.sh
    # ------------------------------------------------------------------
    result = {}
    tmp_path = None
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp_path = tmp.name
        tmp.close()
        copy_from_env("/tmp/insect_nonparametric_result.json", tmp_path)
        with open(tmp_path, "r", encoding="utf-8-sig") as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not load insect_nonparametric_result.json: {e}",
        }
    finally:
        if tmp_path and os.path.exists(tmp_path):
            os.unlink(tmp_path)

    # ------------------------------------------------------------------
    # Output-existence gate
    # ------------------------------------------------------------------
    if not result.get("omv_file_found"):
        return {
            "passed": False,
            "score": 0,
            "feedback": "No .omv file found. The agent did not save the analysis.",
        }

    if not result.get("index_html_found"):
        return {
            "passed": False,
            "score": 0,
            "feedback": ".omv file found but no index.html inside (empty or corrupt).",
        }

    # ------------------------------------------------------------------
    # Criterion 1 (15 pts): File saved at the correct path
    # ------------------------------------------------------------------
    try:
        omv_path = result.get("omv_file_path", "")
        expected_path = "/home/ga/Documents/Jamovi/InsectSprayAnalysis.omv"
        if omv_path == expected_path:
            score += 15
            feedback.append("C1: File saved at correct path (15/15)")
        elif result.get("omv_file_found"):
            # File saved but at wrong path
            score += 8
            feedback.append(f"C1: File saved at {omv_path} instead of expected path (8/15)")
        else:
            feedback.append("C1: No .omv file found (0/15)")
    except Exception as e:
        feedback.append(f"C1: Error checking file path: {e} (0/15)")

    # ------------------------------------------------------------------
    # Criterion 2 (10 pts): Valid .omv structure (ZIP with expected contents)
    # ------------------------------------------------------------------
    try:
        zip_contents = result.get("zip_contents", [])
        file_size = result.get("omv_file_size", 0)
        has_index = "index.html" in zip_contents
        has_meta = "meta" in zip_contents or any("meta" in f for f in zip_contents)
        has_data = any("data" in f.lower() for f in zip_contents)

        if has_index and has_meta and has_data and file_size > 5000:
            score += 10
            feedback.append(f"C2: Valid .omv structure ({file_size} bytes, {len(zip_contents)} entries) (10/10)")
        elif has_index and file_size > 2000:
            score += 7
            feedback.append(f"C2: .omv has index.html but incomplete structure ({file_size} bytes) (7/10)")
        elif file_size > 1000:
            score += 4
            feedback.append(f"C2: .omv exists but minimal structure ({file_size} bytes) (4/10)")
        else:
            feedback.append(f"C2: .omv file too small or missing structure ({file_size} bytes) (0/10)")
    except Exception as e:
        feedback.append(f"C2: Error checking .omv structure: {e} (0/10)")

    # ------------------------------------------------------------------
    # Criterion 3 (20 pts): Descriptives present with count split by spray
    # ------------------------------------------------------------------
    try:
        has_desc = result.get("has_descriptives", False)
        has_split = result.get("has_descriptives_split_spray", False)
        has_count = result.get("has_count_var", False)
        has_spray = result.get("has_spray_var", False)

        if has_desc and has_split and has_count:
            score += 20
            feedback.append("C3: Descriptives with count split by spray (20/20)")
        elif has_desc and has_count and has_spray:
            # Descriptives present with both variables, but split not confirmed
            score += 15
            feedback.append("C3: Descriptives with count and spray variables present (15/20)")
        elif has_desc and has_count:
            score += 10
            feedback.append("C3: Descriptives with count variable but spray split unclear (10/20)")
        elif has_desc:
            score += 5
            feedback.append("C3: Descriptives found but variables not correctly assigned (5/20)")
        else:
            feedback.append("C3: No descriptive statistics found (0/20)")
    except Exception as e:
        feedback.append(f"C3: Error checking descriptives: {e} (0/20)")

    # ------------------------------------------------------------------
    # Criterion 4 (15 pts): Normality test (Shapiro-Wilk) present
    # ------------------------------------------------------------------
    try:
        has_sw = result.get("has_shapiro_wilk", False)

        if has_sw:
            score += 15
            feedback.append("C4: Shapiro-Wilk normality test present (15/15)")
        else:
            # Check the raw HTML for alternative normality indicators
            html_content = result.get("index_html_content", "").lower()
            if "normality" in html_content or "normal distribution" in html_content:
                score += 8
                feedback.append("C4: Normality assessment detected but not Shapiro-Wilk specifically (8/15)")
            elif "q-q" in html_content or "qq plot" in html_content or "qqplot" in html_content:
                score += 6
                feedback.append("C4: Q-Q plot detected as normality check (6/15)")
            else:
                feedback.append("C4: No normality test found (0/15)")
    except Exception as e:
        feedback.append(f"C4: Error checking normality test: {e} (0/15)")

    # ------------------------------------------------------------------
    # Criterion 5 (25 pts): Kruskal-Wallis test with correct variables
    # ------------------------------------------------------------------
    try:
        has_kw = result.get("has_kruskal_wallis", False)
        kw_count = result.get("has_kruskal_wallis_count", False)
        kw_spray = result.get("has_kruskal_wallis_spray", False)

        if has_kw and kw_count and kw_spray:
            score += 25
            feedback.append("C5: Kruskal-Wallis test with count and spray variables (25/25)")
        elif has_kw and (kw_count or kw_spray):
            score += 15
            detail = "count" if kw_count else "spray"
            feedback.append(f"C5: Kruskal-Wallis found with {detail} variable only (15/25)")
        elif has_kw:
            score += 10
            feedback.append("C5: Kruskal-Wallis found but variables not confirmed (10/25)")
        else:
            # Check for any non-parametric test mention in HTML
            html_content = result.get("index_html_content", "").lower()
            if "non-parametric" in html_content or "nonparametric" in html_content:
                score += 5
                feedback.append("C5: Non-parametric test mentioned but no Kruskal-Wallis found (5/25)")
            else:
                feedback.append("C5: No Kruskal-Wallis test found (0/25)")
    except Exception as e:
        feedback.append(f"C5: Error checking Kruskal-Wallis: {e} (0/25)")

    # ------------------------------------------------------------------
    # Criterion 6 (15 pts): Pairwise comparisons present
    # ------------------------------------------------------------------
    try:
        has_pw = result.get("has_pairwise", False)

        if has_pw:
            score += 15
            feedback.append("C6: Pairwise comparisons present (15/15)")
        else:
            # Check the raw HTML more broadly for pairwise-like content
            html_content = result.get("index_html_content", "").lower()
            # Check for multiple comparison patterns in the HTML
            pair_indicators = ["comparison", "multiple compar", "bonferroni",
                               "holm", "tukey", "games-howell", "conover"]
            found_any = False
            for indicator in pair_indicators:
                if indicator in html_content:
                    found_any = True
                    break
            if found_any:
                score += 8
                feedback.append("C6: Some form of multiple comparisons detected (8/15)")
            else:
                feedback.append("C6: No pairwise comparisons found (0/15)")
    except Exception as e:
        feedback.append(f"C6: Error checking pairwise comparisons: {e} (0/15)")

    # ------------------------------------------------------------------
    # Final verdict
    # ------------------------------------------------------------------
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
    }
