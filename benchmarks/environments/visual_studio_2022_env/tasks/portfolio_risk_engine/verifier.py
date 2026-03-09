"""
Verifier for portfolio_risk_engine task.

Scoring (100 points):
  - VaR calculator correctly implemented:     30 pts
    * has Sort + percentile index:   15 pts
    * negates to positive loss:       8 pts
    * not a stub (real logic):        7 pts
  - Sharpe Ratio correctly implemented:       35 pts
    * sqrt(252) annualization:       12 pts
    * mean and std dev computation:  12 pts
    * risk-free rate incorporated:   11 pts
  - Max Drawdown correctly implemented:       20 pts
    * peak tracking:                 10 pts
    * drawdown fraction:             10 pts
  - Build gate: 0 errors:                     15 pts

Pass threshold: 60 points
Build gate: if build_errors > 0, score capped at 50
"""

import json
import math
import os
import re
import shutil
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH  = "C:\\Users\\Docker\\portfolio_risk_engine_result.json"
VAR_PATH     = "C:\\Users\\Docker\\source\\repos\\PortfolioAnalytics\\src\\PortfolioAnalytics\\VaRCalculator.cs"
SHARPE_PATH  = "C:\\Users\\Docker\\source\\repos\\PortfolioAnalytics\\src\\PortfolioAnalytics\\SharpeRatioCalculator.cs"
MDD_PATH     = "C:\\Users\\Docker\\source\\repos\\PortfolioAnalytics\\src\\PortfolioAnalytics\\MaxDrawdownCalculator.cs"


def _has(pattern, text, flags=re.IGNORECASE):
    return bool(re.search(pattern, text, flags))


def _is_stub(src):
    """Return True if the file appears to still be the original stub (no real logic)."""
    has_sort  = _has(r"\.Sort\s*\(", src)
    has_linq  = _has(r"\.(Average|Sum|Min|Max|OrderBy|OrderByDescending)\s*\(", src)
    has_math  = _has(r"Math\.(Sqrt|Abs|Log|Pow)\s*\(", src)
    has_loop  = _has(r"\bfor\b|\bforeach\b|\bwhile\b", src)
    return not (has_sort or has_linq or has_math or has_loop)


def verify_portfolio_risk_engine(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.mkdtemp(prefix="verify_portfolio_")
    try:
        # --- Step 1: Read export result JSON ---
        result = {}
        json_local = os.path.join(tmp, "result.json")
        try:
            copy_from_env(RESULT_PATH, json_local)
            with open(json_local, encoding="utf-8-sig") as f:
                result = json.load(f)
        except FileNotFoundError:
            return {"passed": False, "score": 0,
                    "feedback": "Result JSON not found — export script may not have run"}
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Cannot read result JSON: {e}"}

        # --- Anti-gaming gate ---
        if not result.get("any_file_modified", False):
            return {"passed": False, "score": 0,
                    "feedback": "No calculator files were modified — no work detected"}

        # --- Step 2: Copy source files for independent analysis ---
        def _read_remote(remote_path, local_name):
            local = os.path.join(tmp, local_name)
            try:
                copy_from_env(remote_path, local)
                with open(local, encoding="utf-8-sig") as f:
                    return f.read()
            except Exception:
                return ""

        var_src    = _read_remote(VAR_PATH,    "VaRCalculator.cs")
        sharpe_src = _read_remote(SHARPE_PATH, "SharpeRatioCalculator.cs")
        mdd_src    = _read_remote(MDD_PATH,    "MaxDrawdownCalculator.cs")

        score = 0
        fb    = []

        # ── VaR Calculator (30 pts) ───────────────────────────────────────────
        var_pts = 0

        # Pattern: Sort ascending
        var_has_sort = _has(r"\.Sort\s*\(", var_src) if var_src else result.get("var_has_sort", False)
        # Pattern: percentile index (0.05 or floor)
        var_has_pct  = _has(r"0\.05|[Ff]loor|[Pp]ercentile", var_src) if var_src else result.get("var_has_percentile", False)
        if var_has_sort and var_has_pct:
            var_pts += 15
        elif var_has_sort or var_has_pct:
            var_pts += 7

        # Pattern: negation for positive loss
        var_has_neg = _has(r"\-\s*sorted|\-\s*returns|\-dailyReturns|\- returns|\breturn\s+-\b", var_src) if var_src else result.get("var_has_negate", False)
        if var_has_neg:
            var_pts += 8

        # Not a stub
        stub_check = _is_stub(var_src) if var_src else result.get("var_is_stub", True)
        if not stub_check:
            var_pts += 7

        score += var_pts
        if var_pts >= 25:
            fb.append(f"VaRCalculator: well implemented (+{var_pts}/30)")
        elif var_pts > 0:
            fb.append(f"VaRCalculator: partial implementation (+{var_pts}/30)")
        else:
            fb.append("VaRCalculator: still a stub (0/30)")

        # ── Sharpe Ratio Calculator (35 pts) ──────────────────────────────────
        sharpe_pts = 0

        sharpe_has_sqrt252 = _has(r"Sqrt\s*\(\s*252|252[^;]*Sqrt|[Ss]qrt.*252", sharpe_src) if sharpe_src else result.get("sharpe_has_sqrt252", False)
        if sharpe_has_sqrt252:
            sharpe_pts += 12

        sharpe_has_mean   = _has(r"\.Average\s*\(\)|[Ss]um.*[Cc]ount|[Mm]ean|[Aa]vg", sharpe_src) if sharpe_src else result.get("sharpe_has_mean", False)
        sharpe_has_stddev = _has(r"[Ss]td[Dd]ev|[Vv]ariance|Math\.Sqrt|stdDev|std_dev", sharpe_src) if sharpe_src else result.get("sharpe_has_stddev", False)
        if sharpe_has_mean and sharpe_has_stddev:
            sharpe_pts += 12
        elif sharpe_has_mean or sharpe_has_stddev:
            sharpe_pts += 5

        sharpe_has_rf = _has(r"risk_free|riskFree|rf_daily|rfDaily|/ 252|/252", sharpe_src) if sharpe_src else result.get("sharpe_has_riskfree", False)
        if sharpe_has_rf:
            sharpe_pts += 11

        score += sharpe_pts
        if sharpe_pts >= 30:
            fb.append(f"SharpeRatioCalculator: well implemented (+{sharpe_pts}/35)")
        elif sharpe_pts > 0:
            fb.append(f"SharpeRatioCalculator: partial implementation (+{sharpe_pts}/35)")
        else:
            fb.append("SharpeRatioCalculator: still a stub (0/35)")

        # ── MaxDrawdown Calculator (20 pts) ───────────────────────────────────
        mdd_pts = 0

        mdd_has_peak = _has(r"\bpeak\b|\bPeak\b|[Hh]igh[Ww]ater|running.*max|maxSoFar", mdd_src) if mdd_src else result.get("mdd_has_peak", False)
        if mdd_has_peak:
            mdd_pts += 10

        mdd_has_fraction = _has(r"peak\s*-\s*cum|cum.*-.*peak|/ peak|/\s*peak|drawdown\s*=", mdd_src) if mdd_src else result.get("mdd_has_fraction", False)
        if mdd_has_fraction:
            mdd_pts += 10

        score += mdd_pts
        if mdd_pts >= 15:
            fb.append(f"MaxDrawdownCalculator: well implemented (+{mdd_pts}/20)")
        elif mdd_pts > 0:
            fb.append(f"MaxDrawdownCalculator: partial implementation (+{mdd_pts}/20)")
        else:
            fb.append("MaxDrawdownCalculator: still a stub (0/20)")

        # ── Build gate (15 pts) ───────────────────────────────────────────────
        build_success = result.get("build_success", False)
        build_errors  = result.get("build_errors", 999)

        if build_success and build_errors == 0:
            score += 15
            fb.append("Build: OK — 0 errors (+15)")
        else:
            if score > 50:
                score = 50
                fb.append(f"BUILD FAILED ({build_errors} errors) — score capped at 50")
            else:
                fb.append(f"BUILD FAILED ({build_errors} errors)")

        passed = score >= 60
        return {
            "passed": passed,
            "score": min(score, 100),
            "feedback": " | ".join(fb)
        }

    except Exception as e:
        logger.exception("Verification error")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
