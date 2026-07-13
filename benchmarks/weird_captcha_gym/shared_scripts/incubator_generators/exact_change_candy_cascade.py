from __future__ import annotations

from collections import Counter
import hashlib
import random
from typing import Any


MECHANIC_ID = "exact_change_candy_cascade"
HEIGHT = 5
WIDTH = 5
CANDIES = ("cherry", "lemon", "mint", "plum", "orange")
FORBIDDEN = "black_licorice"
PALETTES = ("soda-pop", "night-shift", "sea-glass", "paper-wrapper")


Coord = tuple[int, int]
Swap = tuple[Coord, Coord]


def _all_swaps() -> list[Swap]:
    swaps: list[Swap] = []
    for row in range(HEIGHT):
        for column in range(WIDTH):
            if column + 1 < WIDTH:
                swaps.append(((row, column), (row, column + 1)))
            if row + 1 < HEIGHT:
                swaps.append(((row, column), (row + 1, column)))
    return swaps


ALL_SWAPS = _all_swaps()


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
            raise ValueError("cascade did not settle")
        score += len(matched) * 10 * wave
        for column in range(WIDTH):
            survivors = [board[row][column] for row in range(HEIGHT) if (row, column) not in matched]
            hole_count = HEIGHT - len(survivors)
            additions = refill[refill_index : refill_index + hole_count]
            if len(additions) != hole_count:
                raise ValueError("refill stream exhausted")
            refill_index += hole_count
            rebuilt = additions + survivors
            for row, candy in enumerate(rebuilt):
                board[row][column] = candy


def _apply(
    board: list[list[str]], refill: list[str], refill_index: int, swap: Swap
) -> tuple[list[list[str]], int, int, int] | None:
    first, second = swap
    if board[first[0]][first[1]] == FORBIDDEN or board[second[0]][second[1]] == FORBIDDEN:
        return None
    swapped = [row[:] for row in board]
    swapped[first[0]][first[1]], swapped[second[0]][second[1]] = (
        swapped[second[0]][second[1]],
        swapped[first[0]][first[1]],
    )
    if not _matches(swapped):
        return None
    return _resolve(swapped, refill, refill_index)


def _serialize_swap(swap: Swap) -> list[list[int]]:
    return [[swap[0][0], swap[0][1]], [swap[1][0], swap[1][1]]]


def _build_solved_instance(rng: random.Random) -> dict[str, Any]:
    for attempt in range(240):
        board = [[rng.choice(CANDIES) for _ in range(WIDTH)] for _ in range(HEIGHT)]
        forbidden = (rng.randrange(HEIGHT), rng.randrange(WIDTH))
        board[forbidden[0]][forbidden[1]] = FORBIDDEN
        if _matches(board):
            continue
        refill = [rng.choice(CANDIES) for _ in range(360)]
        candidates: list[dict[str, Any]] = []
        for first_swap in ALL_SWAPS:
            first = _apply(board, refill, 0, first_swap)
            if first is None:
                continue
            board_after_first, refill_after_first, first_score, first_waves = first
            for second_swap in ALL_SWAPS:
                second = _apply(board_after_first, refill, refill_after_first, second_swap)
                if second is None:
                    continue
                final_board, final_refill, second_score, second_waves = second
                if max(first_waves, second_waves) < 2 or max(first_waves, second_waves) > 7:
                    continue
                candidates.append(
                    {
                        "target_score": first_score + second_score,
                        "solution_swaps": [_serialize_swap(first_swap), _serialize_swap(second_swap)],
                        "move_scores": [first_score, second_score],
                        "wave_counts": [first_waves, second_waves],
                        "final_board": final_board,
                        "final_refill_index": final_refill,
                    }
                )
        score_counts = Counter(candidate["target_score"] for candidate in candidates)
        unique = [candidate for candidate in candidates if score_counts[candidate["target_score"]] == 1]
        if not unique:
            continue
        # Prefer a long, legible cascade, but cap the score so the receipt remains compact.
        unique.sort(
            key=lambda candidate: (
                max(candidate["wave_counts"]),
                sum(candidate["wave_counts"]),
                candidate["target_score"],
            ),
            reverse=True,
        )
        chosen = unique[0]
        return {
            "board": board,
            "refill": refill,
            "forbidden": [forbidden[0], forbidden[1]],
            "attempt": attempt,
            **chosen,
        }
    raise ValueError("could not produce a solver-audited exact-change board")


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    digest = hashlib.sha256(f"{seed}|{MECHANIC_ID}".encode("utf-8")).digest()
    rng = random.Random(int.from_bytes(digest[:8], "big"))
    instance = _build_solved_instance(rng)
    task_id = str(task.get("id") or "exact_change_candy_cascade_seed_0001@0.1")
    challenge_id = hashlib.sha256(f"{seed}|exact-change-candy-cascade".encode("utf-8")).hexdigest()[:12]
    palette = PALETTES[rng.randrange(len(PALETTES))]
    variant_upper_bound = len(PALETTES) * HEIGHT * WIDTH * (len(CANDIES) ** (HEIGHT * WIDTH - 1))
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "challenge_id": challenge_id,
        "prompt": task.get("natural_language")
        or "Make exactly the posted change in two swaps. Never disturb the black licorice.",
        "submit_label": "STAMP EXACT",
        "asset_manifest": "shared_runtime/assets/provenance/incubator_puzzles_v1.json",
        "generator": {
            "name": "exact_change_candy_cascade_v1",
            "search_attempt": instance["attempt"],
            "variant_count": variant_upper_bound,
            "variant_count_kind": "pre-solver-search board/palette upper bound",
        },
        "board": instance["board"],
        "refill_stream": instance["refill"],
        "target_score": instance["target_score"],
        "move_budget": 2,
        "forbidden": {
            "candy": FORBIDDEN,
            "position": instance["forbidden"],
            "rule": "Swapping the black licorice voids the entire receipt immediately.",
        },
        "score_rule": "Each wave pays 10 points per candy multiplied by its cascade wave (1x, 2x, 3x…).",
        "palette": palette,
        "variant_count": variant_upper_bound,
        "variant_count_kind": "pre-solver-search board/palette upper bound",
    }
    ground_truth = {
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "seed": seed,
        "challenge_id": challenge_id,
        "initial_board": instance["board"],
        "refill_stream": instance["refill"],
        "target_score": instance["target_score"],
        "move_budget": 2,
        "forbidden_candy": FORBIDDEN,
        "forbidden_position": instance["forbidden"],
        "solution_swaps": instance["solution_swaps"],
        "solution_move_scores": instance["move_scores"],
        "solution_wave_counts": instance["wave_counts"],
        "solution_final_board": instance["final_board"],
        "solution_refill_index": instance["final_refill_index"],
        "palette": palette,
        "variant_count": variant_upper_bound,
        "variant_count_kind": "pre-solver-search board/palette upper bound",
    }
    return public_state, ground_truth
