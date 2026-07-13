from __future__ import annotations

import math
from typing import Any


MECHANIC_ID = "wrong_number"


def _failure(message: str) -> dict[str, Any]:
    return {"graded": True, "passed": False, "score": 0, "feedback": message}


def _number(value: Any) -> float | None:
    try:
        result = float(value)
    except (TypeError, ValueError):
        return None
    return result if math.isfinite(result) else None


def _integer(value: Any) -> int | None:
    if isinstance(value, bool):
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _wrap(value: float, steps: int) -> float:
    return value % steps


def _circular_distance(first: float, second: float, steps: int) -> float:
    direct = abs(_wrap(first, steps) - _wrap(second, steps))
    return min(direct, steps - direct)


def _alignment(
    line: dict[str, Any], phase: int, skew: int, elapsed_ms: float, qualification: dict[str, Any]
) -> tuple[float, bool]:
    steps = int(qualification["phase_steps"])
    drift = float(line["drift_milli_steps_per_second"]) * elapsed_ms / 1_000_000
    target_phase = _wrap(-float(line["phase_offset_steps"]) - drift, steps)
    phase_error = _circular_distance(float(phase), target_phase, steps)
    skew_error = abs(float(skew) + float(line["skew_offset_steps"]))
    phase_scale = float(qualification["phase_tolerance_milli_steps"]) / 1000
    skew_scale = float(qualification["skew_tolerance_milli_steps"]) / 1000
    distortion = float(line["distortion_milli"]) / 1000
    residual = math.sqrt(
        (phase_error / phase_scale) ** 2
        + (skew_error / skew_scale) ** 2
        + distortion**2
    )
    return residual, residual <= 1


def _identity_error(
    payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]
) -> str | None:
    if {
        str(payload.get("mechanic_id") or ""),
        str(ground_truth.get("mechanic_id") or ""),
        str(public_state.get("mechanic_id") or ""),
    } != {MECHANIC_ID}:
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


def grade(payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]) -> dict[str, Any]:
    identity_error = _identity_error(payload, ground_truth, public_state)
    if identity_error:
        return _failure(identity_error)
    lines = ground_truth.get("lines")
    qualification = ground_truth.get("qualification")
    waveform = ground_truth.get("waveform")
    if not isinstance(lines, list) or len(lines) < 7 or not isinstance(qualification, dict) or not isinstance(waveform, dict):
        return _failure("hidden switchboard contract is malformed")
    if public_state.get("lines") != lines or public_state.get("qualification") != qualification or public_state.get("waveform") != waveform:
        return _failure("public switchboard commitment disagrees with hidden state")
    line_map = {str(line.get("id") or ""): line for line in lines if isinstance(line, dict)}
    if len(line_map) != len(lines) or "" in line_map:
        return _failure("hidden carrier bank is malformed")
    target_line_id = str(ground_truth.get("target_line_id") or "")
    if target_line_id not in line_map:
        return _failure("hidden authorized carrier is missing")

    events = payload.get("events")
    if not isinstance(events, list) or len(events) > 1_200:
        return _failure("switchboard transcript is missing or oversized")
    selected: str | None = None
    phase = 0
    skew = 0
    active: dict[str, Any] | None = None
    successful_trials: list[int] = []
    previous_t = -1.0
    trial_count = 0
    failed_trials = 0

    for index, event in enumerate(events, start=1):
        if not isinstance(event, dict):
            return _failure(f"event {index} is not an object")
        if _integer(event.get("seq")) != index:
            return _failure("switchboard sequence is not contiguous")
        event_t = _number(event.get("t_ms"))
        if event_t is None or event_t < previous_t or event_t > 3_600_000:
            return _failure("switchboard timestamps are invalid")
        previous_t = event_t
        event_type = str(event.get("type") or "")

        if event_type == "line_select":
            if active is not None:
                return _failure("carrier changed during a live lock test")
            line_id = str(event.get("line_id") or "")
            if line_id not in line_map:
                return _failure("unknown carrier selected")
            selected = line_id
            continue

        if event_type == "tune":
            control = str(event.get("control") or "")
            value = _integer(event.get("value"))
            if value is None:
                return _failure("tuning value is invalid")
            if control == "phase":
                if not 0 <= value < int(qualification["phase_steps"]):
                    return _failure("phase tuning left its physical range")
                phase = value
            elif control == "skew":
                if not int(qualification["skew_min"]) <= value <= int(qualification["skew_max"]):
                    return _failure("shape tuning left its physical range")
                skew = value
            else:
                return _failure("unknown tuning control")
            continue

        if event_type == "trial_start":
            if active is not None or selected is None:
                return _failure("lock test began from an invalid patch state")
            if str(event.get("line_id") or "") != selected:
                return _failure("lock-test carrier does not match the patched jack")
            if _integer(event.get("phase")) != phase or _integer(event.get("skew")) != skew:
                return _failure("lock-test controls do not match replay")
            trial_count += 1
            active = {
                "line_id": selected,
                "start_seq": index,
                "start_t": event_t,
                "samples": 0,
                "last_sample_t": None,
                "last_elapsed": 0.0,
                "locked_samples": 0,
                "lock_history": [],
            }
            continue

        if event_type == "trial_sample":
            if active is None:
                return _failure("lock sample occurred outside a trial")
            if str(event.get("line_id") or "") != active["line_id"]:
                return _failure("lock sample changed carriers")
            if _integer(event.get("phase")) != phase or _integer(event.get("skew")) != skew:
                return _failure("lock sample controls do not match replay")
            elapsed = _number(event.get("elapsed_ms"))
            if elapsed is None or elapsed < 0 or abs(elapsed - (event_t - active["start_t"])) > 35:
                return _failure("lock sample elapsed time does not match replay")
            if elapsed > float(qualification["trial_ms"]) + float(qualification["sample_ms"]):
                return _failure("lock sample exceeded the trial window")
            last_sample_t = active["last_sample_t"]
            if last_sample_t is not None and event_t - last_sample_t > float(qualification["maximum_sample_gap_ms"]):
                return _failure("live lock sampling has a discontinuity")
            active["last_sample_t"] = event_t
            active["samples"] += 1
            active["last_elapsed"] = elapsed
            residual, locked = _alignment(line_map[active["line_id"]], phase, skew, elapsed, qualification)
            if bool(event.get("locked")) != locked:
                return _failure("reported carrier lock disagrees with signal replay")
            claimed_residual = _integer(event.get("residual_milli"))
            if claimed_residual is None or abs(claimed_residual - round(residual * 1000)) > 3:
                return _failure("reported carrier residual disagrees with signal replay")
            if locked:
                active["locked_samples"] += 1
            active["lock_history"].append(locked)
            active["lock_history"] = active["lock_history"][-int(qualification["final_window_samples"]):]
            continue

        if event_type == "trial_end":
            if active is None:
                return _failure("lock trial ended without starting")
            if str(event.get("line_id") or "") != active["line_id"]:
                return _failure("lock trial ended on another carrier")
            expected_success = (
                active["line_id"] == target_line_id
                and active["last_elapsed"] >= float(qualification["trial_ms"])
                and active["locked_samples"] >= int(qualification["minimum_lock_samples"])
                and sum(bool(item) for item in active["lock_history"]) >= int(qualification["minimum_final_lock_samples"])
            )
            if bool(event.get("passed_local")) != expected_success:
                return _failure("local lock verdict disagrees with signal replay")
            if _integer(event.get("sample_count")) != active["samples"]:
                return _failure("lock sample count does not match replay")
            if _integer(event.get("locked_sample_count")) != active["locked_samples"]:
                return _failure("locked sample total does not match replay")
            if _integer(event.get("final_window_locked_samples")) != sum(bool(item) for item in active["lock_history"]):
                return _failure("final tracking window does not match replay")
            if expected_success:
                successful_trials.append(int(active["start_seq"]))
            else:
                failed_trials += 1
            active = None
            continue

        return _failure(f"unknown switchboard event {event_type!r}")

    if active is not None:
        return _failure("submission interrupted a live lock test")
    final_phase = _integer(payload.get("final_phase"))
    final_skew = _integer(payload.get("final_skew"))
    if final_phase != phase or final_skew != skew:
        return _failure("submitted tuning controls do not match replay")
    if (str(payload.get("selected_line_id") or "") or None) != selected:
        return _failure("submitted carrier selection does not match replay")
    if _integer(payload.get("trial_count")) != trial_count:
        return _failure("submitted trial count does not match replay")
    successful_seq = _integer(payload.get("successful_trial_start_seq"))
    passed = (
        payload.get("completed") is True
        and selected == target_line_id
        and bool(successful_trials)
        and successful_seq == successful_trials[-1]
    )
    return {
        "graded": True,
        "passed": passed,
        "score": 100 if passed else 0,
        "feedback": (
            f"replayed {trial_count} live carrier trials; sustained locks {len(successful_trials)}; "
            f"local misses {failed_trials}; authorized patch={'yes' if selected == target_line_id else 'no'}"
        ),
    }


def cheat(public_state: dict[str, Any], ground_truth: dict[str, Any]) -> dict[str, Any]:
    del public_state
    return {
        "target_line_id": ground_truth.get("target_line_id"),
        "solution_phase_step": ground_truth.get("solution_phase_step"),
        "solution_skew_step": ground_truth.get("solution_skew_step"),
    }
