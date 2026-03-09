#!/usr/bin/env python3
"""
Verifier for portfolio_deposit_and_alerts task.

Task: Investment Fund Manager setting up 'Fund Alpha' with initial deposit, equity buys,
and comprehensive macro watchlist alerts.
Required:
  Portfolio 'Fund Alpha':
    Deposit: $500,000.00, Jan 2 2024, comment contains 'inception'
    BUY SPY:   300sh @ $470.46, Jan 2 2024, broker $0.00, comment 'core beta allocation'
    BUY BRK.B: 200sh @ $363.21, Jan 2 2024, broker $0.00, comment 'value equity allocation'
  Watchlist 'Fund Alpha Watch':
    SPY:   Fall Below $445.00, Rise Above $510.00
    QQQ:   Fall Below $385.00, Rise Above $440.00
    BRK.B: Fall Below $338.00, Rise Above $395.00
    GLD:   Fall Below $178.00, Rise Above $210.00
    TLT:   Fall Below $89.00,  Rise Above $108.00
    VTI:   Fall Below $225.00, Rise Above $260.00
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/portfolio_deposit_and_alerts_result.json"

PRICE_TOL  = 0.50   # slightly wider for ETF pricing
UNITS_TOL  = 2.0
BROKER_TOL = 0.05
ALERT_TOL  = 3.0    # ±$3.00 for macro ETF alerts
AMOUNT_TOL = 1000.0 # ±$1000 for deposit amount

REQUIRED_DEPOSIT = {
    "amount": 500000.0,
    "date_substr": "Jan 2, 2024",
    "comment_keyword": "inception",
}

REQUIRED_BUYS = {
    "SPY":   {"units": 300.0, "price": 470.46, "date_substr": "Jan 2, 2024", "broker": 0.0, "comment_keyword": "core"},
    "BRK.B": {"units": 200.0, "price": 363.21, "date_substr": "Jan 2, 2024", "broker": 0.0, "comment_keyword": "value"},
}

REQUIRED_ALERTS = {
    "SPY":   {"fall_below": 445.0, "rise_above": 510.0},
    "QQQ":   {"fall_below": 385.0, "rise_above": 440.0},
    "BRK.B": {"fall_below": 338.0, "rise_above": 395.0},
    "GLD":   {"fall_below": 178.0, "rise_above": 210.0},
    "TLT":   {"fall_below":  89.0, "rise_above": 108.0},
    "VTI":   {"fall_below": 225.0, "rise_above": 260.0},
}


def _check_deposit(entry, spec):
    """Returns (pts, max_pts=17, notes)."""
    max_pts = 17
    if not entry:
        return 0, max_pts, ["deposit entry not found"]
    pts = 0
    notes = []

    # Amount: 8 pts
    try:
        amount = float(entry.get("Amount", "0") or "0")
        if abs(amount - spec["amount"]) <= AMOUNT_TOL:
            pts += 8
        else:
            notes.append(f"amount {amount:.2f} != {spec['amount']:.2f}")
    except ValueError:
        notes.append("invalid amount")

    # Date: 4 pts
    date_val = entry.get("Date", "")
    if spec["date_substr"].lower() in date_val.lower():
        pts += 4
    else:
        notes.append(f"date '{date_val}' != '{spec['date_substr']}'")

    # Comment keyword: 5 pts
    comment = entry.get("Comment", "").lower()
    if spec["comment_keyword"].lower() in comment:
        pts += 5
    else:
        notes.append(f"comment missing '{spec['comment_keyword']}'")

    return pts, max_pts, notes


def _check_buy(entry, spec, code):
    """Returns (pts, max_pts=14, notes)."""
    max_pts = 14
    if not entry:
        return 0, max_pts, [f"{code} buy entry not found"]
    pts = 0
    notes = []

    # Units: 4 pts
    try:
        u = float(entry.get("Units", "0") or "0")
        if abs(u - spec["units"]) <= UNITS_TOL:
            pts += 4
        else:
            notes.append(f"units {u} != {spec['units']}")
    except ValueError:
        notes.append("invalid units")

    # Price: 4 pts
    try:
        p = float(entry.get("Purchase Price", "0") or "0")
        if abs(p - spec["price"]) <= PRICE_TOL:
            pts += 4
        else:
            notes.append(f"price {p:.2f} != {spec['price']:.2f}")
    except ValueError:
        notes.append("invalid price")

    # Date: 3 pts
    date_val = entry.get("Date", "")
    if spec["date_substr"].lower() in date_val.lower():
        pts += 3
    else:
        notes.append(f"date '{date_val}' != '{spec['date_substr']}'")

    # Broker: 3 pts
    try:
        b = float(entry.get("Broker", "0") or "0")
        if abs(b - spec["broker"]) <= BROKER_TOL:
            pts += 3
        else:
            notes.append(f"broker {b:.2f} != {spec['broker']:.2f}")
    except ValueError:
        notes.append("invalid broker")

    return pts, max_pts, notes


def _check_alert(watch_entry, code, alert_spec):
    """Returns (pts, max_pts=8, notes)."""
    max_pts = 8
    if not watch_entry:
        return 0, max_pts, [f"{code} not in Fund Alpha Watch"]
    pts = 0
    notes = []

    try:
        fall = float(watch_entry.get("Fall Below", "0") or "0")
        if abs(fall - alert_spec["fall_below"]) <= ALERT_TOL:
            pts += 4
        else:
            notes.append(f"Fall Below {fall:.2f} != {alert_spec['fall_below']:.2f}")
    except (ValueError, TypeError):
        notes.append("invalid Fall Below")

    try:
        rise = float(watch_entry.get("Rise Above", "0") or "0")
        if abs(rise - alert_spec["rise_above"]) <= ALERT_TOL:
            pts += 4
        else:
            notes.append(f"Rise Above {rise:.2f} != {alert_spec['rise_above']:.2f}")
    except (ValueError, TypeError):
        notes.append("invalid Rise Above")

    return pts, max_pts, notes


def verify_portfolio_deposit_and_alerts(traj, env_info, task_info):
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

    # ----------------------------------------------------------------
    # GATE: Fund Alpha portfolio must exist
    # ----------------------------------------------------------------
    portfolio_exists = result.get("portfolio_exists", False)
    watchlist_exists = result.get("watchlist_exists", False)
    deposit_count = result.get("deposit_count", 0)
    buy_count = result.get("buy_count", 0)
    watch_count = result.get("watch_count", 0)

    if not portfolio_exists and deposit_count == 0 and buy_count == 0 and watch_count == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "GATE FAIL: 'Fund Alpha' portfolio not created; no deposits, buys, or watchlist entries found.",
            "subscores": {}
        }

    total_score = 0
    feedback_parts = []
    subscores = {}

    # Portfolio exists: 3 pts
    if portfolio_exists:
        total_score += 3
        subscores["portfolio_created"] = 3
    else:
        subscores["portfolio_created"] = 0
        feedback_parts.append("Portfolio 'Fund Alpha': NOT CREATED")

    # Deposit entry
    deposit = result.get("deposit_first")
    pts, max_pts, notes = _check_deposit(deposit, REQUIRED_DEPOSIT)
    total_score += pts
    subscores["deposit"] = pts
    status = "PASS" if pts == max_pts else (f"PARTIAL {pts}/{max_pts}" if pts > 0 else "FAIL")
    msg = f"DEPOSIT $500K: {status}"
    if notes:
        msg += f" ({', '.join(notes)})"
    feedback_parts.append(msg)

    # Buy transactions
    for code, spec in REQUIRED_BUYS.items():
        entry = result.get(f"buy_{code.lower().replace('.', '')}")
        pts, max_pts, notes = _check_buy(entry, spec, code)
        total_score += pts
        subscores[f"buy_{code}"] = pts
        status = "PASS" if pts == max_pts else (f"PARTIAL {pts}/{max_pts}" if pts > 0 else "FAIL")
        msg = f"BUY {code}: {status}"
        if notes:
            msg += f" ({', '.join(notes)})"
        feedback_parts.append(msg)

    # Watchlist alerts
    for code, alert_spec in REQUIRED_ALERTS.items():
        watch_key = f"watch_{code.lower().replace('.', '')}"
        watch_entry = result.get(watch_key)
        pts, max_pts, notes = _check_alert(watch_entry, code, alert_spec)
        total_score += pts
        subscores[f"alert_{code}"] = pts
        status = "PASS" if pts == max_pts else (f"PARTIAL {pts}/{max_pts}" if pts > 0 else "FAIL")
        msg = f"ALERT {code}: {status}"
        if notes:
            msg += f" ({', '.join(notes)})"
        feedback_parts.append(msg)

    total_score = min(total_score, 100)
    passed = total_score >= 60

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
    }
