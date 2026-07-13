from __future__ import annotations

from typing import Any


MECHANIC_ID = "insider_trading_captcha"
SIDES = {"hold", "buy", "sell"}


def _identity_error(
    payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]
) -> str | None:
    mechanic_ids = {
        str(payload.get("mechanic_id") or ""),
        str(ground_truth.get("mechanic_id") or ""),
        str(public_state.get("mechanic_id") or ""),
    }
    if mechanic_ids != {MECHANIC_ID}:
        return "mechanic identity mismatch"
    challenge_ids = {
        str(payload.get("challenge_id") or ""),
        str(ground_truth.get("challenge_id") or ""),
        str(public_state.get("challenge_id") or ""),
    }
    if len(challenge_ids) != 1 or "" in challenge_ids:
        return "challenge identity mismatch"
    task_ids = {
        str(payload.get("task_id") or ""),
        str(ground_truth.get("task_id") or ""),
        str(public_state.get("task_id") or ""),
    }
    if len(task_ids) != 1 or "" in task_ids:
        return "task identity mismatch"
    return None


def _normalize_orders(raw: Any, count: int, delay: int) -> tuple[list[str] | None, str | None]:
    if not isinstance(raw, list) or len(raw) != count:
        return None, f"order tape must contain exactly {count} ticks"
    actions: list[str] = []
    for index, item in enumerate(raw):
        if not isinstance(item, dict):
            return None, "order tape contains a malformed row"
        try:
            tick = int(item.get("tick"))
        except (TypeError, ValueError):
            return None, "order tick is invalid"
        side = str(item.get("side") or "").lower()
        if tick != index or side not in SIDES:
            return None, "order tape is not a monotonic tick-indexed transcript"
        if index >= count - delay and side != "hold":
            return None, "an order was placed too late to settle"
        actions.append(side)
    return actions, None


def _replay(
    prices: list[int], actions: list[str], initial_cash: int, fee: int, max_position: int, delay: int
) -> tuple[bool, int, int, list[dict[str, int | str]], str]:
    cash = initial_cash
    position = 0
    ledger: list[dict[str, int | str]] = []
    for tick, price in enumerate(prices):
        placed_tick = tick - delay
        side = actions[placed_tick] if placed_tick >= 0 else "hold"
        if side == "buy":
            if position >= max_position:
                return False, cash, position, ledger, "position limit exceeded at settlement"
            if cash < price + fee:
                return False, cash, position, ledger, "insufficient cash at settlement"
            cash -= price + fee
            position += 1
        elif side == "sell":
            if position <= 0:
                return False, cash, position, ledger, "short sale attempted at settlement"
            cash += price - fee
            position -= 1
        if side != "hold":
            ledger.append(
                {
                    "placed_tick": placed_tick,
                    "settle_tick": tick,
                    "side": side,
                    "price_cents": price,
                    "fee_cents": fee,
                    "cash_after_cents": cash,
                    "position_after": position,
                }
            )
    return True, cash, position, ledger, "replayed"


def _normalize_ledger(raw: Any) -> list[dict[str, int | str]] | None:
    if not isinstance(raw, list):
        return None
    normalized: list[dict[str, int | str]] = []
    integer_fields = (
        "placed_tick",
        "settle_tick",
        "price_cents",
        "fee_cents",
        "cash_after_cents",
        "position_after",
    )
    for item in raw:
        if not isinstance(item, dict):
            return None
        try:
            row: dict[str, int | str] = {field: int(item.get(field)) for field in integer_fields}
        except (TypeError, ValueError):
            return None
        row["side"] = str(item.get("side") or "").lower()
        normalized.append(row)
    return normalized


def grade(payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]) -> dict[str, Any]:
    error = _identity_error(payload, ground_truth, public_state)
    if error:
        return {"graded": True, "passed": False, "feedback": error}
    try:
        prices = [int(value) for value in ground_truth.get("prices_cents") or []]
        initial_cash = int(ground_truth.get("initial_cash_cents"))
        fee = int(ground_truth.get("fee_cents"))
        max_position = int(ground_truth.get("max_position"))
        delay = int(ground_truth.get("order_delay_ticks"))
        target = int(ground_truth.get("target_profit_cents"))
    except (TypeError, ValueError):
        return {"graded": True, "passed": False, "feedback": "hidden market contract is malformed"}
    if not prices or delay < 3 or fee < 0 or max_position < 4:
        return {"graded": True, "passed": False, "feedback": "hidden market contract is invalid"}
    if public_state.get("runtime_price_stream_cents") != prices:
        return {"graded": True, "passed": False, "feedback": "public quote commitment does not match hidden tape"}

    actions, order_error = _normalize_orders(payload.get("orders"), len(prices), delay)
    if order_error or actions is None:
        return {"graded": True, "passed": False, "feedback": order_error or "invalid order tape"}
    valid, cash, position, expected_ledger, replay_feedback = _replay(
        prices, actions, initial_cash, fee, max_position, delay
    )
    actual_ledger = _normalize_ledger(payload.get("settlement_ledger"))
    ledger_matches = actual_ledger == expected_ledger
    try:
        claimed_cash = int((payload.get("final") or {}).get("cash_cents"))
        claimed_position = int((payload.get("final") or {}).get("position"))
    except (TypeError, ValueError):
        claimed_cash = -1
        claimed_position = -999
    profit = cash - initial_cash
    round_trip = "buy" in actions and "sell" in actions
    passed = (
        valid
        and ledger_matches
        and claimed_cash == cash
        and claimed_position == position
        and position == 0
        and round_trip
        and profit >= target
    )
    return {
        "graded": True,
        "passed": passed,
        "feedback": (
            f"{replay_feedback}; profit {profit}¢/{target}¢; position {position}; "
            f"settlements {len(expected_ledger)}; ledger={'exact' if ledger_matches else 'mismatch'}"
        ),
    }


def cheat(public_state: dict[str, Any], ground_truth: dict[str, Any]) -> dict[str, Any]:
    if (
        str(public_state.get("mechanic_id") or "") != MECHANIC_ID
        or str(ground_truth.get("mechanic_id") or "") != MECHANIC_ID
        or str(public_state.get("challenge_id") or "") != str(ground_truth.get("challenge_id") or "")
    ):
        return {"error": "challenge identity mismatch"}
    return {
        "prices_cents": ground_truth.get("prices_cents") or [],
        "solver_actions": ground_truth.get("solver_actions") or [],
        "solver_ledger": ground_truth.get("solver_ledger") or [],
        "max_profit_cents": ground_truth.get("max_profit_cents"),
    }
