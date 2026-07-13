from __future__ import annotations

from typing import Any


MECHANIC_ID = "polyrhythm_customs"


def _identity_error(
    payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]
) -> str | None:
    if {
        str(payload.get("mechanic_id") or ""),
        str(ground_truth.get("mechanic_id") or ""),
        str(public_state.get("mechanic_id") or ""),
    } != {MECHANIC_ID}:
        return "mechanic identity mismatch"
    challenges = {
        str(payload.get("challenge_id") or ""),
        str(ground_truth.get("challenge_id") or ""),
        str(public_state.get("challenge_id") or ""),
    }
    if len(challenges) != 1 or "" in challenges:
        return "challenge identity mismatch"
    task_ids = {
        str(payload.get("task_id") or ""),
        str(ground_truth.get("task_id") or ""),
        str(public_state.get("task_id") or ""),
    }
    if len(task_ids) != 1 or "" in task_ids:
        return "task identity mismatch"
    return None


def _normalize_transcript(raw: Any, lane_ids: set[str], max_time: float) -> tuple[list[dict[str, Any]] | None, str | None]:
    if not isinstance(raw, list) or len(raw) > 100:
        return None, "performance transcript is missing or too long"
    normalized: list[dict[str, Any]] = []
    previous_time = -1.0
    held: set[str] = set()
    for index, item in enumerate(raw):
        if not isinstance(item, dict):
            return None, "performance transcript contains a malformed event"
        try:
            seq = int(item.get("seq"))
            at_ms = round(float(item.get("t_ms")), 2)
        except (TypeError, ValueError):
            return None, "performance event time is invalid"
        lane = str(item.get("lane") or "")
        event_type = str(item.get("type") or "").lower()
        source = str(item.get("source") or "").lower()
        if seq != index or lane not in lane_ids or event_type not in {"down", "up"}:
            return None, "performance events are not a normalized monotonic transcript"
        if source not in {"keyboard", "pointer"}:
            return None, "performance event source is invalid"
        if at_ms < previous_time or at_ms < -50 or at_ms > max_time + 750:
            return None, "performance event timestamp is out of bounds"
        if event_type == "down":
            if lane in held:
                return None, "duplicate press without release"
            held.add(lane)
        else:
            if lane not in held:
                return None, "release without a matching press"
            held.remove(lane)
        previous_time = at_ms
        normalized.append({"seq": seq, "lane": lane, "type": event_type, "t_ms": at_ms, "source": source})
    if held:
        return None, "performance ended with a held lane"
    return normalized, None


def _pair_notes(transcript: list[dict[str, Any]]) -> list[dict[str, Any]]:
    downs: dict[str, dict[str, Any]] = {}
    notes: list[dict[str, Any]] = []
    for event in transcript:
        lane = str(event["lane"])
        if event["type"] == "down":
            downs[lane] = event
        else:
            down = downs.pop(lane)
            notes.append(
                {
                    "lane": lane,
                    "start_ms": float(down["t_ms"]),
                    "duration_ms": float(event["t_ms"]) - float(down["t_ms"]),
                }
            )
    notes.sort(key=lambda note: (float(note["start_ms"]), str(note["lane"])))
    return notes


def _match_notes(expected: list[dict[str, Any]], actual: list[dict[str, Any]], start_window: float):
    matched: dict[str, dict[str, Any]] = {}
    used: set[int] = set()
    for note in sorted(expected, key=lambda item: (float(item["start_ms"]), str(item["lane"]))):
        candidates = [
            (abs(float(candidate["start_ms"]) - float(note["start_ms"])), index, candidate)
            for index, candidate in enumerate(actual)
            if index not in used
            and str(candidate["lane"]) == str(note["lane"])
            and abs(float(candidate["start_ms"]) - float(note["start_ms"])) <= start_window
        ]
        if not candidates:
            continue
        _, index, candidate = min(candidates, key=lambda item: (item[0], item[1]))
        used.add(index)
        matched[str(note["id"])] = candidate
    return matched, len(actual) - len(used)


def grade(payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]) -> dict[str, Any]:
    error = _identity_error(payload, ground_truth, public_state)
    if error:
        return {"graded": True, "passed": False, "feedback": error}
    expected = ground_truth.get("expected_notes") or []
    chords = ground_truth.get("chords") or []
    settings = ground_truth.get("settings") or {}
    if expected != public_state.get("score"):
        return {"graded": True, "passed": False, "feedback": "preview score does not match hidden score commitment"}
    try:
        performance_ms = float(settings.get("performance_ms"))
        start_window = float(settings.get("start_window_ms"))
        duration_tolerance = float(settings.get("duration_tolerance_ms"))
        chord_window = float(settings.get("chord_window_ms"))
        threshold = float(settings.get("pass_accuracy"))
        lane_ids = {str(lane["id"]) for lane in ground_truth.get("lanes") or []}
    except (TypeError, ValueError, KeyError):
        return {"graded": True, "passed": False, "feedback": "hidden performance contract is malformed"}
    transcript, transcript_error = _normalize_transcript(payload.get("transcript"), lane_ids, performance_ms)
    if transcript_error or transcript is None:
        return {"graded": True, "passed": False, "feedback": transcript_error or "invalid transcript"}
    actual_notes = _pair_notes(transcript)
    matched, extras = _match_notes(expected, actual_notes, start_window)

    points = 0.0
    total = float(len(expected))
    for note in expected:
        actual = matched.get(str(note.get("id") or ""))
        if actual is None:
            continue
        expected_duration = float(note.get("duration_ms") or 0)
        actual_duration = float(actual["duration_ms"])
        if str(note.get("kind") or "") == "hold":
            points += 1.0
            total += 1.0
            if abs(actual_duration - expected_duration) <= duration_tolerance:
                points += 1.0
        elif 25 <= actual_duration <= 430:
            points += 1.0

    chord_points = 0
    for chord in chords:
        total += 1.0
        chord_notes = [note for note in expected if note.get("chord_id") == chord.get("id")]
        actual_starts = [
            float(matched[str(note["id"])]["start_ms"])
            for note in chord_notes
            if str(note["id"]) in matched
        ]
        if len(actual_starts) == len(chord_notes) and max(actual_starts) - min(actual_starts) <= chord_window:
            points += 1.0
            chord_points += 1

    points = max(0.0, points - extras * 0.5)
    accuracy = points / total if total else 0.0
    passed = accuracy >= threshold and len(matched) >= 1 and chord_points == len(chords)
    return {
        "graded": True,
        "passed": passed,
        "feedback": (
            f"accuracy {accuracy * 100:.1f}%/{threshold * 100:.0f}%; notes {len(matched)}/{len(expected)}; "
            f"holds {sum(1 for note in expected if note.get('kind') == 'hold')}; "
            f"chords {chord_points}/{len(chords)}; extras {extras}"
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
        "expected_notes": ground_truth.get("expected_notes") or [],
        "chords": ground_truth.get("chords") or [],
        "settings": ground_truth.get("settings") or {},
    }
