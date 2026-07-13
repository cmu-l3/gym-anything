from __future__ import annotations

from typing import Any


MECHANIC_ID = "exact_change_candy_cascade"
HEIGHT = 5
WIDTH = 5
FORBIDDEN = "black_licorice"


Coord = tuple[int, int]


def _fail(feedback: str) -> dict[str, Any]:
    return {"graded": True, "passed": False, "feedback": feedback}


def _bind(payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]) -> str | None:
    if str(payload.get("mechanic_id") or "") != MECHANIC_ID:
        return "payload mechanic mismatch"
    if str(ground_truth.get("mechanic_id") or "") != MECHANIC_ID:
        return "ground-truth mechanic mismatch"
    if str(public_state.get("mechanic_id") or "") != MECHANIC_ID:
        return "public-state mechanic mismatch"
    challenge_id = str(ground_truth.get("challenge_id") or "")
    if not challenge_id or str(payload.get("challenge_id") or "") != challenge_id:
        return "stale challenge"
    if str(public_state.get("challenge_id") or "") != challenge_id:
        return "public-state challenge mismatch"
    task_id = str(ground_truth.get("task_id") or "")
    if not task_id or str(payload.get("task_id") or "") != task_id:
        return "payload task mismatch"
    if str(public_state.get("task_id") or "") != task_id:
        return "public-state task mismatch"
    return None


def _matches(board: list[list[str]]) -> set[Coord]:
    matched: set[Coord] = set()
    for row in range(HEIGHT):
        start = 0
        while start < WIDTH:
            candy = board[row][start]
            end = start + 1
            while end < WIDTH and board[row][end] == candy:
                end += 1
            if candy != FORBIDDEN and end - start >= 3:
                matched.update((row, column) for column in range(start, end))
            start = end
    for column in range(WIDTH):
        start = 0
        while start < HEIGHT:
            candy = board[start][column]
            end = start + 1
            while end < HEIGHT and board[end][column] == candy:
                end += 1
            if candy != FORBIDDEN and end - start >= 3:
                matched.update((row, column) for row in range(start, end))
            start = end
    return matched


def _resolve(
    board: list[list[str]], refill: list[str], refill_index: int
) -> tuple[list[list[str]], int, int, int]:
    board = [row[:] for row in board]
    score = 0
    wave = 0
    while True:
        matched = _matches(board)
        if not matched:
            return board, refill_index, score, wave
        wave += 1
        if wave > 20:
            raise ValueError("cascade exceeded safety limit")
        score += len(matched) * 10 * wave
        for column in range(WIDTH):
            survivors = [board[row][column] for row in range(HEIGHT) if (row, column) not in matched]
            holes = HEIGHT - len(survivors)
            additions = refill[refill_index : refill_index + holes]
            if len(additions) != holes:
                raise ValueError("refill stream exhausted")
            refill_index += holes
            rebuilt = additions + survivors
            for row, candy in enumerate(rebuilt):
                board[row][column] = candy


def _coord(value: Any) -> Coord:
    if not isinstance(value, list) or len(value) != 2:
        raise ValueError("coordinate must be a two-item list")
    row, column = value
    if isinstance(row, bool) or isinstance(column, bool) or not isinstance(row, int) or not isinstance(column, int):
        raise ValueError("coordinate values must be integers")
    if not (0 <= row < HEIGHT and 0 <= column < WIDTH):
        raise ValueError("coordinate lies outside the board")
    return row, column


def _board(value: Any) -> list[list[str]]:
    if not isinstance(value, list) or len(value) != HEIGHT:
        raise ValueError("board has the wrong height")
    board: list[list[str]] = []
    for row in value:
        if not isinstance(row, list) or len(row) != WIDTH or not all(isinstance(item, str) for item in row):
            raise ValueError("board row is malformed")
        board.append(row[:])
    return board


def _contract(ground_truth: dict[str, Any], public_state: dict[str, Any]) -> tuple[list[list[str]], list[str], int, int]:
    board = _board(ground_truth.get("initial_board"))
    public_board = _board(public_state.get("board"))
    if public_board != board:
        raise ValueError("public initial board differs from hidden contract")
    refill = ground_truth.get("refill_stream")
    public_refill = public_state.get("refill_stream")
    if not isinstance(refill, list) or not refill or not all(isinstance(item, str) for item in refill):
        raise ValueError("hidden refill stream is malformed")
    if public_refill != refill:
        raise ValueError("public refill stream differs from hidden contract")
    target = ground_truth.get("target_score")
    move_budget = ground_truth.get("move_budget")
    if isinstance(target, bool) or not isinstance(target, int) or target <= 0:
        raise ValueError("target score is malformed")
    if move_budget != 2:
        raise ValueError("move budget contract is malformed")
    if public_state.get("target_score") != target or public_state.get("move_budget") != move_budget:
        raise ValueError("public score contract differs from hidden contract")
    forbidden = public_state.get("forbidden")
    if not isinstance(forbidden, dict) or forbidden.get("candy") != FORBIDDEN:
        raise ValueError("forbidden-candy contract is malformed")
    if forbidden.get("position") != ground_truth.get("forbidden_position"):
        raise ValueError("forbidden-candy position mismatch")
    return board, list(refill), target, move_budget


def grade(payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]) -> dict[str, Any]:
    binding_error = _bind(payload, ground_truth, public_state)
    if binding_error:
        return _fail(binding_error)
    try:
        board, refill, target, move_budget = _contract(ground_truth, public_state)
    except (TypeError, ValueError) as exc:
        return _fail(f"invalid candy contract: {exc}")

    transcript = payload.get("swaps")
    if not isinstance(transcript, list) or not (1 <= len(transcript) <= 40):
        return _fail("swap transcript is missing or outside limits")

    refill_index = 0
    total_score = 0
    valid_moves = 0
    invalid_swaps = 0
    forbidden_activated = False
    max_wave = 0
    terminal = False
    for index, event in enumerate(transcript, start=1):
        if terminal:
            return _fail("transcript continues after a terminal outcome")
        if not isinstance(event, dict) or event.get("sequence") != index:
            return _fail(f"swap {index} has an invalid sequence")
        try:
            first = _coord(event.get("from"))
            second = _coord(event.get("to"))
        except ValueError as exc:
            return _fail(f"swap {index} is malformed: {exc}")
        if abs(first[0] - second[0]) + abs(first[1] - second[1]) != 1:
            return _fail(f"swap {index} is not adjacent")

        wave_count = 0
        if board[first[0]][first[1]] == FORBIDDEN or board[second[0]][second[1]] == FORBIDDEN:
            outcome = "forbidden"
            forbidden_activated = True
            terminal = True
        else:
            swapped = [row[:] for row in board]
            swapped[first[0]][first[1]], swapped[second[0]][second[1]] = (
                swapped[second[0]][second[1]],
                swapped[first[0]][first[1]],
            )
            if not _matches(swapped):
                outcome = "invalid"
                invalid_swaps += 1
            else:
                outcome = "valid"
                valid_moves += 1
                if valid_moves > move_budget:
                    return _fail("valid-move budget exceeded")
                try:
                    board, refill_index, earned, wave_count = _resolve(swapped, refill, refill_index)
                except ValueError as exc:
                    return _fail(f"cascade replay failed: {exc}")
                total_score += earned
                max_wave = max(max_wave, wave_count)
                if total_score > target or valid_moves == move_budget:
                    terminal = True

        expected = {"outcome": outcome, "score_after": total_score, "wave_count": wave_count}
        for field, value in expected.items():
            if event.get(field) != value:
                return _fail(f"swap {index} has inconsistent {field}: expected {value!r}")

    if payload.get("final_board") != board:
        return _fail("submitted board does not match replay")
    if payload.get("refill_index") != refill_index:
        return _fail("submitted refill cursor does not match replay")
    if payload.get("score") != total_score:
        return _fail("submitted score does not match replay")
    if payload.get("valid_moves") != valid_moves or payload.get("invalid_swaps") != invalid_swaps:
        return _fail("submitted move counters do not match replay")
    if payload.get("forbidden_activated") is not forbidden_activated:
        return _fail("submitted forbidden-candy state does not match replay")

    passed = (
        payload.get("completed") is True
        and not forbidden_activated
        and valid_moves == move_budget
        and total_score == target
        and max_wave >= 2
    )
    return {
        "graded": True,
        "passed": passed,
        "feedback": (
            f"exact-change replay {total_score}/{target}; valid swaps {valid_moves}/{move_budget}; "
            f"invalid swaps {invalid_swaps}; longest cascade {max_wave} wave(s); "
            f"licorice {'activated' if forbidden_activated else 'untouched'}"
        ),
    }


def cheat(public_state: dict[str, Any], ground_truth: dict[str, Any]) -> dict[str, Any]:
    return {
        "swaps": ground_truth.get("solution_swaps") or [],
        "move_scores": ground_truth.get("solution_move_scores") or [],
        "wave_counts": ground_truth.get("solution_wave_counts") or [],
        "instruction": "Perform the two adjacent swaps in order, then stamp the exact receipt.",
        "answers": [],
    }
