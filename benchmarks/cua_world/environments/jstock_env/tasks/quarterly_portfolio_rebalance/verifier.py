#!/usr/bin/env python3
"""
Verifier for quarterly_portfolio_rebalance task.

Task: Execute a quarterly portfolio review consisting of:
  - Deposit: $25,000, March 1 2024, comment containing "capital"
  - Dividend: AAPL $111.00, March 10 2024, comment containing "dividend"
  - Sell AAPL: 50 shares @ $215.00, March 15 2024
  - Sell NVDA: 15 shares @ $750.00, March 15 2024
  - Buy XOM: floor($25,000 / $105.00) = 238 shares @ $105.00, March 15 2024
  - Buy KO:  floor($20,000 / $58.00)  = 344 shares @ $58.00, March 15 2024
  - Buy JNJ: floor($12,000 / $162.50) = 73 shares @ $162.50, March 15 2024
  - Watchlist "Q1 Rebalance Watch" with 6 stocks + 12 alert values
  - Export buy portfolio to /home/ga/Documents/portfolio_q1_export.csv

Scoring (100 pts, pass >= 60):
  Deposit:      10 pts (amount=5, date=3, comment=2)
  Dividend:      8 pts (code=2, amount=3, date=2, comment=1)
  Sell AAPL:    10 pts (units=5, price=3, date=2)
  Sell NVDA:    10 pts (units=5, price=3, date=2)
  Buy XOM:      10 pts (symbol=2, units=4, price=2, date=2)
  Buy KO:       10 pts (symbol=2, units=4, price=2, date=2)
  Buy JNJ:      10 pts (symbol=2, units=4, price=2, date=2)
  Watchlist:     6 pts (exists=3, has_6_stocks=3)
  Alerts:       18 pts (12 values x 1.5 pts each)
  Export:        8 pts (exists+new=3, has_symbols=5)
  Total:       100 pts
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/quarterly_portfolio_rebalance_result.json"

# Tolerances
PRICE_TOL = 0.50
UNITS_TOL = 2.0
AMOUNT_TOL = 500.0
ALERT_TOL = 2.00


def _safe_float(val, default=0.0):
    try:
        return float(val or default)
    except (ValueError, TypeError):
        return default


def _date_match(date_str, expected_substr):
    """Check if date contains the expected month/year pattern."""
    if not date_str or not expected_substr:
        return False
    # Normalize both for comparison
    d = date_str.lower().replace(",", "").replace("  ", " ").strip()
    e = expected_substr.lower().replace(",", "").replace("  ", " ").strip()
    # Check for substring match or component match
    if e in d:
        return True
    # Also accept numeric formats like 3/15/24 or 03/15/2024
    month_map = {
        "jan": "1", "feb": "2", "mar": "3", "apr": "4",
        "may": "5", "jun": "6", "jul": "7", "aug": "8",
        "sep": "9", "oct": "10", "nov": "11", "dec": "12"
    }
    for mon, num in month_map.items():
        if mon in e:
            # Extract expected day and year
            parts = e.split()
            if len(parts) >= 3:
                exp_day = parts[1].strip().lstrip("0")
                exp_year = parts[2].strip()
                # Check if numeric format matches
                if f"{num}/{exp_day}" in d or f"0{num}/{exp_day}" in d:
                    if exp_year in d or exp_year[-2:] in d:
                        return True
            break
    return False


def verify_quarterly_portfolio_rebalance(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")

    result = {}
    if copy_from_env:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env(RESULT_PATH, tmp.name)
            with open(tmp.name, "r", encoding="utf-8") as f:
                result = json.load(f)
        except Exception as e:
            logger.warning(f"Failed to load result JSON: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Could not read result file: {e}.",
                "subscores": {}
            }
        finally:
            try:
                os.unlink(tmp.name)
            except Exception:
                pass

    # ================================================================
    # GATE CHECK: if nothing was done at all, fail immediately
    # ================================================================
    sell_count = result.get("sell_count", 0)
    buy_count = result.get("buy_count", 0)
    deposit_count = result.get("deposit_count", 0)
    dividend_count = result.get("dividend_count", 0)
    watchlist_exists = result.get("watchlist_exists", False)

    # The initial state has 4 buy entries, 0 sells, 1 deposit, 0 dividends
    if sell_count == 0 and buy_count <= 4 and deposit_count <= 1 and dividend_count == 0 and not watchlist_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "GATE FAIL: No changes detected — no sells, no new buys, no new deposits, no dividends, no watchlist.",
            "subscores": {}
        }

    total_score = 0
    feedback_parts = []
    subscores = {}

    # ================================================================
    # 1. DEPOSIT: $25,000 on March 1, 2024 (10 pts)
    # ================================================================
    deposit = result.get("deposit_new")
    dep_pts = 0
    dep_notes = []
    if deposit:
        # Amount: 5 pts
        amt = _safe_float(deposit.get("Amount"))
        if abs(amt - 25000.0) <= AMOUNT_TOL:
            dep_pts += 5
        else:
            dep_notes.append(f"amount {amt:.0f} != 25000")
        # Date: 3 pts
        if _date_match(deposit.get("Date", ""), "Mar 01, 2024"):
            dep_pts += 3
        else:
            dep_notes.append(f"date '{deposit.get('Date', '')}' != Mar 01 2024")
        # Comment: 2 pts
        comment = (deposit.get("Comment", "") or "").lower()
        if "capital" in comment or "q1" in comment or "contribution" in comment:
            dep_pts += 2
        else:
            dep_notes.append("comment missing keyword")
    else:
        dep_notes.append("$25K deposit not found")
    total_score += dep_pts
    subscores["deposit"] = dep_pts
    feedback_parts.append(f"DEPOSIT: {dep_pts}/10" + (f" ({', '.join(dep_notes)})" if dep_notes else ""))

    # ================================================================
    # 2. DIVIDEND: AAPL $111.00, March 10 2024 (8 pts)
    # ================================================================
    dividend = result.get("dividend_aapl")
    div_pts = 0
    div_notes = []
    if dividend:
        # Code: 2 pts (already matched by key)
        div_pts += 2
        # Amount: 3 pts
        amt = _safe_float(dividend.get("Amount"))
        if abs(amt - 111.0) <= 5.0:
            div_pts += 3
        else:
            div_notes.append(f"amount {amt:.2f} != 111.00")
        # Date: 2 pts
        if _date_match(dividend.get("Date", ""), "Mar 10, 2024"):
            div_pts += 2
        else:
            div_notes.append(f"date '{dividend.get('Date', '')}' != Mar 10 2024")
        # Comment: 1 pt
        comment = (dividend.get("Comment", "") or "").lower()
        if "dividend" in comment or "q1" in comment:
            div_pts += 1
        else:
            div_notes.append("comment missing keyword")
    else:
        div_notes.append("AAPL dividend not found")
    total_score += div_pts
    subscores["dividend_aapl"] = div_pts
    feedback_parts.append(f"DIVIDEND AAPL: {div_pts}/8" + (f" ({', '.join(div_notes)})" if div_notes else ""))

    # ================================================================
    # 3. SELL AAPL: 50 shares @ $215.00, March 15 2024 (10 pts)
    # ================================================================
    def _check_sell(entry, code, exp_units, exp_price, exp_date, max_pts=10):
        pts = 0
        notes = []
        if not entry:
            return 0, [f"{code} sell not found"]
        # Units: 5 pts
        u = _safe_float(entry.get("Units"))
        if abs(u - exp_units) <= UNITS_TOL:
            pts += 5
        else:
            notes.append(f"units {u} != {exp_units}")
        # Price: 3 pts
        p = _safe_float(entry.get("Selling Price"))
        if abs(p - exp_price) <= PRICE_TOL:
            pts += 3
        else:
            notes.append(f"price {p:.2f} != {exp_price:.2f}")
        # Date: 2 pts
        if _date_match(entry.get("Date", ""), exp_date):
            pts += 2
        else:
            notes.append(f"date '{entry.get('Date', '')}' != {exp_date}")
        return pts, notes

    sell_aapl_pts, sell_aapl_notes = _check_sell(result.get("sell_aapl"), "AAPL", 50, 215.00, "Mar 15, 2024")
    total_score += sell_aapl_pts
    subscores["sell_aapl"] = sell_aapl_pts
    feedback_parts.append(f"SELL AAPL: {sell_aapl_pts}/10" + (f" ({', '.join(sell_aapl_notes)})" if sell_aapl_notes else ""))

    # ================================================================
    # 4. SELL NVDA: 15 shares @ $750.00, March 15 2024 (10 pts)
    # ================================================================
    sell_nvda_pts, sell_nvda_notes = _check_sell(result.get("sell_nvda"), "NVDA", 15, 750.00, "Mar 15, 2024")
    total_score += sell_nvda_pts
    subscores["sell_nvda"] = sell_nvda_pts
    feedback_parts.append(f"SELL NVDA: {sell_nvda_pts}/10" + (f" ({', '.join(sell_nvda_notes)})" if sell_nvda_notes else ""))

    # ================================================================
    # 5-7. BUY XOM, KO, JNJ (10 pts each)
    # ================================================================
    def _check_buy(entry, code, exp_units, exp_price, exp_date, max_pts=10):
        pts = 0
        notes = []
        if not entry:
            return 0, [f"{code} buy not found"]
        # Symbol present: 2 pts
        pts += 2
        # Units: 4 pts
        u = _safe_float(entry.get("Units"))
        if abs(u - exp_units) <= UNITS_TOL:
            pts += 4
        else:
            notes.append(f"units {u} != {exp_units}")
        # Price: 2 pts
        p = _safe_float(entry.get("Purchase Price"))
        if abs(p - exp_price) <= PRICE_TOL:
            pts += 2
        else:
            notes.append(f"price {p:.2f} != {exp_price:.2f}")
        # Date: 2 pts
        if _date_match(entry.get("Date", ""), exp_date):
            pts += 2
        else:
            notes.append(f"date '{entry.get('Date', '')}' != {exp_date}")
        return pts, notes

    buy_specs = [
        ("buy_xom", "XOM", 238, 105.00, "Mar 15, 2024"),
        ("buy_ko", "KO", 344, 58.00, "Mar 15, 2024"),
        ("buy_jnj_new", "JNJ (new)", 73, 162.50, "Mar 15, 2024"),
    ]
    for key, label, exp_units, exp_price, exp_date in buy_specs:
        entry = result.get(key)
        pts, notes = _check_buy(entry, label, exp_units, exp_price, exp_date)
        total_score += pts
        subscores[f"buy_{label.lower().replace(' ', '_').replace('(', '').replace(')', '')}"] = pts
        feedback_parts.append(f"BUY {label}: {pts}/10" + (f" ({', '.join(notes)})" if notes else ""))

    # ================================================================
    # 8. WATCHLIST: "Q1 Rebalance Watch" exists + 6 stocks (6 pts)
    # ================================================================
    wl_pts = 0
    wl_notes = []
    if result.get("watchlist_exists"):
        wl_pts += 3
    else:
        wl_notes.append("watchlist not created")

    # Check for 6 expected stocks
    stocks_found = 0
    for code in ["AAPL", "MSFT", "NVDA", "JNJ", "XOM", "KO"]:
        if result.get(f"watch_{code.lower()}"):
            stocks_found += 1
    if stocks_found >= 6:
        wl_pts += 3
    elif stocks_found >= 4:
        wl_pts += 2
    elif stocks_found >= 2:
        wl_pts += 1
    if stocks_found < 6:
        wl_notes.append(f"{stocks_found}/6 stocks in watchlist")

    total_score += wl_pts
    subscores["watchlist"] = wl_pts
    feedback_parts.append(f"WATCHLIST: {wl_pts}/6" + (f" ({', '.join(wl_notes)})" if wl_notes else ""))

    # ================================================================
    # 9. ALERTS: 12 values x 1.5 pts each = 18 pts
    # ================================================================
    alert_specs = {
        "AAPL": {"fall_below": 176.23, "rise_above": 204.05},
        "MSFT": {"fall_below": 399.00, "rise_above": 462.00},
        "NVDA": {"fall_below": 584.25, "rise_above": 676.50},
        "JNJ":  {"fall_below": 152.00, "rise_above": 176.00},
        "XOM":  {"fall_below": 99.75,  "rise_above": 115.50},
        "KO":   {"fall_below": 55.10,  "rise_above": 63.80},
    }
    alert_pts = 0
    alert_notes = []
    for code, spec in alert_specs.items():
        watch_entry = result.get(f"watch_{code.lower()}")
        if not watch_entry:
            alert_notes.append(f"{code}: not in watchlist")
            continue
        # Fall Below: 1.5 pts
        fb = _safe_float(watch_entry.get("Fall Below"))
        if fb > 0 and abs(fb - spec["fall_below"]) <= ALERT_TOL:
            alert_pts += 1.5
        elif fb > 0:
            alert_notes.append(f"{code} FB {fb:.2f}!={spec['fall_below']:.2f}")
        else:
            alert_notes.append(f"{code} FB not set")
        # Rise Above: 1.5 pts
        ra = _safe_float(watch_entry.get("Rise Above"))
        if ra > 0 and abs(ra - spec["rise_above"]) <= ALERT_TOL:
            alert_pts += 1.5
        elif ra > 0:
            alert_notes.append(f"{code} RA {ra:.2f}!={spec['rise_above']:.2f}")
        else:
            alert_notes.append(f"{code} RA not set")

    alert_pts = int(alert_pts)  # Floor to integer
    total_score += alert_pts
    subscores["alerts"] = alert_pts
    alert_summary = f"{alert_pts}/18"
    if alert_notes:
        alert_summary += f" ({', '.join(alert_notes[:5])}{'...' if len(alert_notes) > 5 else ''})"
    feedback_parts.append(f"ALERTS: {alert_summary}")

    # ================================================================
    # 10. EXPORT FILE (8 pts)
    # ================================================================
    exp_pts = 0
    exp_notes = []
    if result.get("export_exists"):
        if result.get("export_is_new") and result.get("export_size", 0) > 50:
            exp_pts += 3
        elif result.get("export_size", 0) > 0:
            exp_pts += 1
            exp_notes.append("file exists but stale or small")
        # Check for expected symbols
        syms = result.get("export_symbols", [])
        sym_count = len(syms)
        if sym_count >= 5:
            exp_pts += 5
        elif sym_count >= 3:
            exp_pts += 3
        elif sym_count >= 1:
            exp_pts += 1
        if sym_count < 7:
            exp_notes.append(f"{sym_count}/7 symbols in export")
    else:
        exp_notes.append("export file not found")

    total_score += exp_pts
    subscores["export"] = exp_pts
    feedback_parts.append(f"EXPORT: {exp_pts}/8" + (f" ({', '.join(exp_notes)})" if exp_notes else ""))

    # ================================================================
    # FINAL RESULT
    # ================================================================
    total_score = min(total_score, 100)
    passed = total_score >= 60

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
    }
