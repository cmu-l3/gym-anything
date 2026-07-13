#!/usr/bin/env python3
from __future__ import annotations

import argparse
import importlib.util
import json
import math
import mimetypes
import os
import secrets
import time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlparse


class PuzzleServer(BaseHTTPRequestHandler):
    app_dir: Path
    state_dir: Path

    server_version = "WeirdCaptchaServer/0.1"

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/health":
            self._send_json({"ok": True, "ts": time.time()})
            return
        if parsed.path == "/state":
            state = self._try_regenerate_current_task(reason="refresh")
            if state:
                self._send_json(state)
                return
            self._send_json_file(self.state_dir / "public_state.json")
            return
        if parsed.path == "/result":
            self._send_json_file(self.state_dir / "result.json")
            return
        self._send_static(parsed.path)

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/cheat":
            self._handle_cheat()
            return
        if parsed.path != "/result":
            self._send_json({"error": "unknown endpoint"}, status=HTTPStatus.NOT_FOUND)
            return
        try:
            payload = self._read_json()
        except ValueError as exc:
            self._send_json({"error": str(exc)}, status=HTTPStatus.BAD_REQUEST)
            return
        payload.setdefault("submitted_at", time.time())
        self.state_dir.mkdir(parents=True, exist_ok=True)
        grade = self._grade_submission(payload)
        payload["server_grade"] = grade
        if grade.get("graded") and not grade.get("passed"):
            self._archive_attempt(payload)
            next_state = self._try_regenerate_current_task(reason="fail")
            response = {
                "ok": True,
                "passed": False,
            }
            if next_state:
                response["state"] = next_state
            self._send_json(response)
            return

        self._write_json(self.state_dir / "result.json", payload)
        response = {"ok": True}
        if grade.get("graded"):
            response.update({
                "passed": bool(grade.get("passed")),
            })
        self._send_json(response)

    def _handle_cheat(self) -> None:
        expected_password = self._cheat_password()
        if not expected_password:
            self._send_json({"error": "not found"}, status=HTTPStatus.NOT_FOUND)
            return
        try:
            payload = self._read_json()
        except ValueError as exc:
            self._send_json({"error": str(exc)}, status=HTTPStatus.BAD_REQUEST)
            return
        if str(payload.get("password") or "") != expected_password:
            self._send_json({"error": "forbidden"}, status=HTTPStatus.FORBIDDEN)
            return

        public_state = self._read_json_file(self.state_dir / "public_state.json")
        ground_truth = self._read_json_file(self.state_dir / "ground_truth.json")
        tile_positions = {
            str(tile.get("id")): index + 1
            for index, tile in enumerate(public_state.get("tiles") or [])
            if isinstance(tile, dict)
        }
        answers = []
        response = {
            "ok": True,
            "mechanic_id": ground_truth.get("mechanic_id"),
            "task_id": ground_truth.get("task_id"),
            "seed": ground_truth.get("seed"),
        }
        incubator_grader = self._load_incubator_grader(str(ground_truth.get("mechanic_id") or ""))
        incubator_cheat = getattr(incubator_grader, "cheat", None) if incubator_grader is not None else None
        if callable(incubator_cheat):
            details = incubator_cheat(public_state, ground_truth)
            if isinstance(details, dict):
                response.update(details)
            self._send_json(response)
            return
        if ground_truth.get("mechanic_id") == "cursor_lens_reveal":
            expected_click = ground_truth.get("expected_click") or {}
            response["target"] = {
                "target_id": ground_truth.get("target_id"),
                "symbol": ground_truth.get("target_symbol"),
                "x": expected_click.get("x"),
                "y": expected_click.get("y"),
                "radius": expected_click.get("radius"),
            }
        elif ground_truth.get("mechanic_id") == "board_game_captcha":
            solution = ground_truth.get("solution") or {}
            response["move"] = {
                "cell_id": ground_truth.get("solution_cell_id"),
                "row": solution.get("row"),
                "col": solution.get("col"),
                "player": solution.get("player"),
                "objective": ground_truth.get("objective"),
            }
        elif ground_truth.get("mechanic_id") == "modifier_stack_image_grid":
            for tile_id in ground_truth.get("expected_tile_ids") or []:
                tile_id = str(tile_id)
                answers.append({
                    "tile_id": tile_id,
                    "position": tile_positions.get(tile_id),
                })
            response["target_kind"] = ground_truth.get("target_kind")
            response["answers"] = answers
        elif ground_truth.get("mechanic_id") == "semantic_drag_drop_absurdity":
            response["assignments"] = ground_truth.get("expected_assignments") or {}
        elif ground_truth.get("mechanic_id") == "reload_interruption":
            response["answers"] = ground_truth.get("answers") or {}
            response["interruptions"] = ground_truth.get("expected_interruptions") or []
        elif ground_truth.get("mechanic_id") == "rotate_wrong_thing_upright":
            response["rotation"] = {
                "target_cue": ground_truth.get("target_cue"),
                "target_angle": ground_truth.get("target_angle"),
                "tolerance": ground_truth.get("tolerance"),
            }
        elif ground_truth.get("mechanic_id") == "bureaucratic_signature_trap":
            response["required_marks"] = ground_truth.get("required_marks") or []
        elif ground_truth.get("mechanic_id") == "wonky_text_hostile_rendering":
            response["token"] = ground_truth.get("token")
        elif ground_truth.get("mechanic_id") == "temporal_memory_first_change":
            response["target"] = {
                "object_id": ground_truth.get("target_object_id"),
                "kind": ground_truth.get("target_kind"),
                "first_change_ms": ground_truth.get("first_change_ms"),
            }
        elif ground_truth.get("mechanic_id") == "motion_only_ghost_jigsaw":
            response["positions"] = ground_truth.get("expected_positions") or {}
        elif ground_truth.get("mechanic_id") == "cursor_constellation_hunt":
            response["target"] = ground_truth.get("expected_click") or {}
            response["shape"] = ground_truth.get("shape")
        elif ground_truth.get("mechanic_id") == "parallel_grillmaster":
            response["targets"] = ground_truth.get("targets") or {}
        elif ground_truth.get("mechanic_id") == "rotating_keyboard":
            response["target"] = ground_truth.get("target")
        elif ground_truth.get("mechanic_id") == "slot_reel_capture":
            response["sequence"] = ground_truth.get("sequence")
        elif ground_truth.get("mechanic_id") == "domino_autopsy":
            response["target_slots"] = ground_truth.get("target_slots") or []
        elif ground_truth.get("mechanic_id") == "consequences_boss":
            response["kind_choices"] = ground_truth.get("kind_choices") or {}
        elif ground_truth.get("mechanic_id") == "popup_exorcist":
            response["blocker_id"] = ground_truth.get("blocker_id")
        elif ground_truth.get("mechanic_id") == "funeral_ritual":
            response["ritual"] = ground_truth.get("required_events") or []
        elif ground_truth.get("mechanic_id") == "slime_commute":
            response["goal"] = ground_truth.get("goal") or {}
        else:
            for tile_id in ground_truth.get("expected_tile_ids") or []:
                tile_id = str(tile_id)
                answers.append({
                    "tile_id": tile_id,
                    "position": tile_positions.get(tile_id),
                })
            response["answers"] = answers
        self._send_json(response)

    def log_message(self, fmt: str, *args: object) -> None:
        print("[%s] %s" % (self.log_date_time_string(), fmt % args), flush=True)

    def _read_json(self) -> dict:
        try:
            length = int(self.headers.get("content-length", "0"))
        except ValueError as exc:
            raise ValueError("invalid content-length") from exc
        raw = self.rfile.read(max(0, length))
        try:
            data = json.loads(raw.decode("utf-8"))
        except json.JSONDecodeError as exc:
            raise ValueError("invalid json") from exc
        if not isinstance(data, dict):
            raise ValueError("json body must be an object")
        return data

    def _send_json_file(self, path: Path) -> None:
        if not path.exists():
            self._send_json({"error": f"{path.name} is not ready"}, status=HTTPStatus.NOT_FOUND)
            return
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except Exception as exc:
            self._send_json({"error": f"cannot read {path.name}: {exc}"}, status=HTTPStatus.INTERNAL_SERVER_ERROR)
            return
        self._send_json(data)

    def _read_json_file(self, path: Path) -> dict:
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except FileNotFoundError:
            return {}
        except Exception as exc:
            return {"_error": str(exc)}
        return data if isinstance(data, dict) else {}

    def _write_json(self, path: Path, data: dict) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(path.suffix + ".tmp")
        tmp.write_text(json.dumps(data, indent=2, sort_keys=True), encoding="utf-8")
        os.replace(tmp, path)

    def _grade_submission(self, payload: dict) -> dict:
        mechanic_id = str(payload.get("mechanic_id") or "")
        reviewed_overhauls = {
            "surreal_apple_on_tree_grid",
            "cursor_lens_reveal",
            "modifier_stack_image_grid",
            "board_game_captcha",
            "consequences_boss",
            "popup_exorcist",
            "slime_commute",
            "semantic_drag_drop_absurdity",
            "reload_interruption",
            "rotate_wrong_thing_upright",
            "bureaucratic_signature_trap",
            "wonky_text_hostile_rendering",
            "temporal_memory_first_change",
        }
        if mechanic_id in reviewed_overhauls:
            return self._grade_incubator_submission(payload)
        if mechanic_id == "cursor_lens_reveal":
            return self._grade_cursor_lens_submission(payload)
        if mechanic_id == "board_game_captcha":
            return self._grade_board_game_submission(payload)
        if mechanic_id == "modifier_stack_image_grid":
            return self._grade_tile_set_submission(payload)
        if mechanic_id == "semantic_drag_drop_absurdity":
            return self._grade_semantic_drag_submission(payload)
        if mechanic_id == "reload_interruption":
            return self._grade_reload_submission(payload)
        if mechanic_id == "rotate_wrong_thing_upright":
            return self._grade_rotate_submission(payload)
        if mechanic_id == "bureaucratic_signature_trap":
            return self._grade_form_submission(payload)
        if mechanic_id == "wonky_text_hostile_rendering":
            return self._grade_wonky_text_submission(payload)
        if mechanic_id == "temporal_memory_first_change":
            return self._grade_temporal_submission(payload)
        if mechanic_id == "motion_only_ghost_jigsaw":
            return self._grade_ghost_jigsaw_submission(payload)
        if mechanic_id == "cursor_constellation_hunt":
            return self._grade_constellation_submission(payload)
        if mechanic_id == "parallel_grillmaster":
            return self._grade_grillmaster_submission(payload)
        if mechanic_id == "rotating_keyboard":
            return self._grade_rotating_keyboard_submission(payload)
        if mechanic_id == "slot_reel_capture":
            return self._grade_slot_reel_submission(payload)
        if mechanic_id == "domino_autopsy":
            return self._grade_domino_submission(payload)
        if mechanic_id == "consequences_boss":
            return self._grade_consequences_submission(payload)
        if mechanic_id == "popup_exorcist":
            return self._grade_popup_submission(payload)
        if mechanic_id == "funeral_ritual":
            return self._grade_funeral_submission(payload)
        if mechanic_id == "slime_commute":
            return self._grade_slime_submission(payload)
        if self._load_incubator_grader(mechanic_id) is not None:
            return self._grade_incubator_submission(payload)
        if mechanic_id != "surreal_apple_on_tree_grid":
            return {"graded": False}
        return self._grade_tile_set_submission(payload)

    def _load_incubator_grader(self, mechanic_id: str):
        if not mechanic_id or not mechanic_id.replace("_", "").isalnum():
            return None
        grader_path = Path(__file__).resolve().parent / "incubator_graders" / f"{mechanic_id}.py"
        if not grader_path.is_file():
            return None
        spec = importlib.util.spec_from_file_location(f"weird_captcha_grader_{mechanic_id}", grader_path)
        if spec is None or spec.loader is None:
            return None
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def _grade_incubator_submission(self, payload: dict) -> dict:
        mechanic_id = str(payload.get("mechanic_id") or "")
        public_state = self._read_json_file(self.state_dir / "public_state.json")
        ground_truth = self._read_json_file(self.state_dir / "ground_truth.json")
        if mechanic_id != str(ground_truth.get("mechanic_id") or ""):
            return {"graded": True, "passed": False, "feedback": "mechanic mismatch"}
        if str(payload.get("challenge_id") or "") != str(ground_truth.get("challenge_id") or ""):
            return {"graded": True, "passed": False, "feedback": "stale challenge"}
        module = self._load_incubator_grader(mechanic_id)
        grader = getattr(module, "grade", None) if module is not None else None
        if not callable(grader):
            return {"graded": False}
        result = grader(payload, ground_truth, public_state)
        if not isinstance(result, dict):
            return {"graded": True, "passed": False, "feedback": "invalid grader result"}
        result.setdefault("graded", True)
        result.setdefault("passed", False)
        return result

    def _grade_tile_set_submission(self, payload: dict) -> dict:
        ground_truth = self._read_json_file(self.state_dir / "ground_truth.json")
        expected = set(str(item) for item in ground_truth.get("expected_tile_ids") or [])
        selected = set(str(item) for item in payload.get("selected_tile_ids") or [])
        true_positive = expected & selected
        false_positive = selected - expected
        missed = expected - selected
        passed = selected == expected
        return {
            "graded": True,
            "passed": passed,
            "feedback": (
                f"correct {len(true_positive)}/{len(expected)}; "
                f"extra {len(false_positive)}; missed {len(missed)}"
            ),
        }

    def _grade_cursor_lens_submission(self, payload: dict) -> dict:
        ground_truth = self._read_json_file(self.state_dir / "ground_truth.json")
        expected = ground_truth.get("expected_click") or {}
        click = payload.get("click") or {}
        try:
            expected_x = float(expected.get("x"))
            expected_y = float(expected.get("y"))
            radius = float(expected.get("radius"))
            actual_x = float(click.get("x"))
            actual_y = float(click.get("y"))
        except (TypeError, ValueError):
            return {
                "graded": True,
                "passed": False,
                "feedback": "click coordinate missing or invalid",
            }
        distance = math.hypot(actual_x - expected_x, actual_y - expected_y)
        passed = distance <= radius
        return {
            "graded": True,
            "passed": passed,
            "feedback": f"distance {distance:.2f}; radius {radius:.2f}",
        }

    def _grade_board_game_submission(self, payload: dict) -> dict:
        ground_truth = self._read_json_file(self.state_dir / "ground_truth.json")
        expected = str(ground_truth.get("solution_cell_id") or "")
        selected = str(payload.get("selected_cell_id") or "")
        passed = bool(expected) and selected == expected
        return {
            "graded": True,
            "passed": passed,
            "feedback": "move accepted" if passed else "move rejected",
        }

    def _grade_semantic_drag_submission(self, payload: dict) -> dict:
        ground_truth = self._read_json_file(self.state_dir / "ground_truth.json")
        expected = {
            str(key): str(value)
            for key, value in (ground_truth.get("expected_assignments") or {}).items()
        }
        placements = {
            str(key): str(value)
            for key, value in (payload.get("placements") or {}).items()
            if value is not None
        }
        passed = placements == expected
        correct = sum(1 for key, value in expected.items() if placements.get(key) == value)
        return {
            "graded": True,
            "passed": passed,
            "feedback": f"assignments {correct}/{len(expected)}",
        }

    def _grade_reload_submission(self, payload: dict) -> dict:
        ground_truth = self._read_json_file(self.state_dir / "ground_truth.json")
        expected = set(str(item) for item in ground_truth.get("expected_interruptions") or [])
        cleared = set(str(item) for item in payload.get("cleared_interruptions") or [])
        completed = payload.get("completed") is True
        failed = bool(payload.get("failed_interruption_id"))
        passed = completed and not failed and cleared == expected
        return {
            "graded": True,
            "passed": passed,
            "feedback": f"completed={completed}; cleared {len(cleared)}/{len(expected)}",
        }

    def _grade_rotate_submission(self, payload: dict) -> dict:
        ground_truth = self._read_json_file(self.state_dir / "ground_truth.json")
        try:
            target = float(ground_truth.get("target_angle"))
            tolerance = float(ground_truth.get("tolerance") or 10)
            submitted = float(payload.get("angle"))
        except (TypeError, ValueError):
            return {"graded": True, "passed": False, "feedback": "angle missing"}
        delta = abs((submitted - target + 180.0) % 360.0 - 180.0)
        return {
            "graded": True,
            "passed": delta <= tolerance,
            "feedback": f"angle delta {delta:.2f}",
        }

    def _grade_form_submission(self, payload: dict) -> dict:
        ground_truth = self._read_json_file(self.state_dir / "ground_truth.json")
        expected = [
            (str(mark.get("field_id")), str(mark.get("mark_type")))
            for mark in ground_truth.get("required_marks") or []
        ]
        marks = [
            (str(mark.get("field_id")), str(mark.get("mark_type")))
            for mark in payload.get("marks") or []
            if isinstance(mark, dict)
        ]
        passed = sorted(marks) == sorted(expected)
        correct = len(set(marks) & set(expected))
        return {
            "graded": True,
            "passed": passed,
            "feedback": f"marks {correct}/{len(expected)}",
        }

    def _normalize_token(self, value: object) -> str:
        return "".join(ch for ch in str(value or "").upper() if ch.isalnum())

    def _grade_wonky_text_submission(self, payload: dict) -> dict:
        ground_truth = self._read_json_file(self.state_dir / "ground_truth.json")
        expected = set(self._normalize_token(item) for item in ground_truth.get("accepted") or [])
        submitted = self._normalize_token(payload.get("text"))
        passed = submitted in expected
        return {
            "graded": True,
            "passed": passed,
            "feedback": "token accepted" if passed else "token rejected",
        }

    def _grade_temporal_submission(self, payload: dict) -> dict:
        ground_truth = self._read_json_file(self.state_dir / "ground_truth.json")
        expected = str(ground_truth.get("target_object_id") or "")
        selected = str(payload.get("selected_object_id") or "")
        passed = bool(expected) and selected == expected
        return {
            "graded": True,
            "passed": passed,
            "feedback": "object accepted" if passed else "object rejected",
        }

    def _grade_ghost_jigsaw_submission(self, payload: dict) -> dict:
        ground_truth = self._read_json_file(self.state_dir / "ground_truth.json")
        expected = {str(key): int(value) for key, value in (ground_truth.get("expected_positions") or {}).items()}
        try:
            placements = {str(key): int(value) for key, value in (payload.get("placements") or {}).items()}
        except (TypeError, ValueError):
            placements = {}
        correct = sum(1 for key, value in expected.items() if placements.get(key) == value)
        passed = bool(expected) and placements == expected
        return {"graded": True, "passed": passed, "feedback": f"pieces {correct}/{len(expected)}"}

    def _grade_constellation_submission(self, payload: dict) -> dict:
        ground_truth = self._read_json_file(self.state_dir / "ground_truth.json")
        expected = ground_truth.get("expected_click") or {}
        click = payload.get("click") or {}
        try:
            distance = math.hypot(float(click.get("x")) - float(expected.get("x")), float(click.get("y")) - float(expected.get("y")))
            radius = float(expected.get("radius"))
        except (TypeError, ValueError):
            return {"graded": True, "passed": False, "feedback": "click missing"}
        return {"graded": True, "passed": distance <= radius, "feedback": f"distance {distance:.2f}"}

    def _grade_grillmaster_submission(self, payload: dict) -> dict:
        ground_truth = self._read_json_file(self.state_dir / "ground_truth.json")
        targets = ground_truth.get("targets") or {}
        durations = payload.get("durations_ms") or {}
        correct = 0
        for food_id, target in targets.items():
            try:
                elapsed = float(durations.get(food_id))
                target_ms = float(target.get("target_ms"))
                tolerance_ms = float(target.get("tolerance_ms"))
            except (TypeError, ValueError):
                continue
            if abs(elapsed - target_ms) <= tolerance_ms:
                correct += 1
        passed = bool(targets) and correct == len(targets) and set(durations) == set(targets)
        return {"graded": True, "passed": passed, "feedback": f"foods {correct}/{len(targets)}"}

    def _grade_rotating_keyboard_submission(self, payload: dict) -> dict:
        ground_truth = self._read_json_file(self.state_dir / "ground_truth.json")
        expected = str(ground_truth.get("target") or "")
        submitted = str(payload.get("text") or "").upper()
        passed = bool(expected) and submitted == expected
        return {"graded": True, "passed": passed, "feedback": "code accepted" if passed else "code rejected"}

    def _grade_slot_reel_submission(self, payload: dict) -> dict:
        ground_truth = self._read_json_file(self.state_dir / "ground_truth.json")
        expected = str(ground_truth.get("sequence") or "")
        submitted = str(payload.get("captured_sequence") or "").upper()
        expected_reels = [str(item) for item in ground_truth.get("reel_ids") or []]
        frozen_reels = [str(item) for item in payload.get("frozen_reel_ids") or []]
        wrong_keys = int(payload.get("wrong_keys") or 0)
        max_strikes = int(ground_truth.get("max_strikes") or 3)
        passed = bool(expected) and submitted == expected and frozen_reels == expected_reels and wrong_keys < max_strikes
        return {"graded": True, "passed": passed, "feedback": f"captured {len(submitted)}/{len(expected)}; strikes {wrong_keys}/{max_strikes}"}

    def _grade_domino_submission(self, payload: dict) -> dict:
        ground_truth = self._read_json_file(self.state_dir / "ground_truth.json")
        loose_ids = set(str(item) for item in ground_truth.get("loose_ids") or [])
        raw = payload.get("placements") or {}
        if set(str(key) for key in raw) != loose_ids:
            return {"graded": True, "passed": False, "feedback": "not all loose dominoes were placed"}
        try:
            for item in raw.values():
                float(item.get("x")); float(item.get("y")); float(item.get("angle"))
        except (TypeError, ValueError):
            return {"graded": True, "passed": False, "feedback": "domino placement is invalid"}
        expected = set(str(item) for item in ground_truth.get("expected_body_ids") or [])
        first = str(ground_truth.get("first_body_id") or "")
        bell = str(ground_truth.get("bell_body_id") or "bell-body")
        minimum_swing = float(ground_truth.get("minimum_bell_swing_radians") or 0.03)
        try:
            bell_swing = abs(float(payload.get("bell_peak_angle") or 0.0))
        except (TypeError, ValueError):
            bell_swing = 0.0
        allowed = expected | {bell}
        graph = {label: set() for label in allowed}
        valid_pairs = 0
        for pair in payload.get("collision_pairs") or []:
            if not isinstance(pair, list) or len(pair) != 2:
                continue
            left, right = str(pair[0]), str(pair[1])
            if left not in allowed or right not in allowed or left == right:
                continue
            graph[left].add(right); graph[right].add(left); valid_pairs += 1
        seen = set()
        queue = [first] if first in graph else []
        while queue:
            current = queue.pop()
            if current in seen:
                continue
            seen.add(current); queue.extend(graph[current] - seen)
        connected = len((expected | {bell}) & seen)
        physics_engine = str(payload.get("physics_engine") or "")
        passed = payload.get("run_completed") is True and payload.get("bell_hit") is True and bell_swing >= minimum_swing and physics_engine == "matter-js@0.20.0" and expected | {bell} <= seen
        return {"graded": True, "passed": passed, "feedback": f"rigid-body collision graph {connected}/{len(expected) + 1}; contacts {valid_pairs}; physical bell swing={bell_swing:.3f} rad"}

    def _grade_consequences_submission(self, payload: dict) -> dict:
        ground_truth = self._read_json_file(self.state_dir / "ground_truth.json")
        valid = {str(key): [str(item) for item in value] for key, value in (ground_truth.get("valid_choices") or {}).items()}
        kind = {str(key): str(value) for key, value in (ground_truth.get("kind_choices") or {}).items()}
        choices = {str(key): str(value) for key, value in (payload.get("choices") or {}).items()}
        actions = {str(key): str(value) for key, value in (payload.get("boss_actions") or {}).items()}
        if set(choices) != set(valid) or set(actions) != set(valid):
            return {"graded": True, "passed": False, "feedback": "the consequence ledger is incomplete"}
        legal = all(choices[scene_id] in valid[scene_id] for scene_id in valid)
        correct = sum(
            1 for scene_id in valid
            if actions.get(scene_id) == ("protect" if choices.get(scene_id) == kind.get(scene_id) else "exploit")
        )
        passed = legal and correct == len(valid)
        return {"graded": True, "passed": passed, "feedback": f"consequences answered {correct}/{len(valid)}"}

    def _grade_popup_submission(self, payload: dict) -> dict:
        ground_truth = self._read_json_file(self.state_dir / "ground_truth.json")
        expected = set(str(item) for item in ground_truth.get("popup_ids") or [])
        cleared = set(str(item) for item in payload.get("cleared_popup_ids") or [])
        mode = str(payload.get("mode") or "manual")
        trigger = str(payload.get("trigger_popup_id") or "")
        valid_mode = mode == "manual" or (mode == "purge" and trigger == str(ground_truth.get("blocker_id") or ""))
        passed = bool(expected) and cleared == expected and valid_mode
        return {"graded": True, "passed": passed, "feedback": f"windows cleared {len(cleared & expected)}/{len(expected)}; mode={mode}"}

    def _grade_funeral_submission(self, payload: dict) -> dict:
        ground_truth = self._read_json_file(self.state_dir / "ground_truth.json")
        required_events = [str(item) for item in ground_truth.get("required_events") or []]
        events = [str(item) for item in payload.get("events") or []]
        max_cells = int(ground_truth.get("moss_cells") or 24)
        cells = set()
        for item in payload.get("brushed_cells") or []:
            try:
                value = int(item)
            except (TypeError, ValueError):
                continue
            if 0 <= value < max_cells:
                cells.add(value)
        flowers = set(str(item) for item in payload.get("gathered_flower_ids") or [])
        expected_flowers = set(str(item) for item in ground_truth.get("flower_ids") or [])
        threshold = int(ground_truth.get("brush_threshold") or 17)
        completed = payload.get("completed") is True
        passed = completed and events == required_events and len(cells) >= threshold and flowers == expected_flowers
        return {"graded": True, "passed": passed, "feedback": f"ritual {len(events)}/{len(required_events)}; moss {len(cells)}/{threshold}; flowers {len(flowers)}/{len(expected_flowers)}"}

    def _grade_slime_submission(self, payload: dict) -> dict:
        ground_truth = self._read_json_file(self.state_dir / "ground_truth.json")
        visited = set()
        for item in payload.get("visited_rows") or []:
            try:
                visited.add(int(item))
            except (TypeError, ValueError):
                continue
        required = set(int(item) for item in ground_truth.get("required_rows") or [])
        final = payload.get("final") or {}
        goal = ground_truth.get("goal") or {}
        try:
            deaths = int(payload.get("deaths") or 0)
            final_x, final_y = int(final.get("x")), int(final.get("y"))
            goal_x, goal_y = int(goal.get("x")), int(goal.get("y"))
        except (TypeError, ValueError):
            return {"graded": True, "passed": False, "feedback": "commute result is invalid"}
        max_deaths = int(ground_truth.get("max_deaths") or 4)
        passed = payload.get("completed") is True and required <= visited and (final_x, final_y) == (goal_x, goal_y) and deaths < max_deaths
        return {"graded": True, "passed": passed, "feedback": f"rows {len(visited & required)}/{len(required)}; wipeouts {deaths}/{max_deaths}"}

    def _archive_attempt(self, payload: dict) -> None:
        path = self.state_dir / "attempts.jsonl"
        with path.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(payload, sort_keys=True) + "\n")

    def _cheat_password(self) -> str | None:
        value = os.environ.get("WEIRD_CAPTCHA_CHEAT_PASSWORD")
        if value:
            return value
        password_path = self.state_dir / "cheat_password.txt"
        try:
            value = password_path.read_text(encoding="utf-8").strip()
        except FileNotFoundError:
            return None
        return value or None

    def _load_setup_module(self):
        setup_path = self.app_dir.parent.parent / "shared_scripts" / "setup_task.py"
        if not setup_path.exists():
            return None
        spec = importlib.util.spec_from_file_location("weird_captcha_setup_task", setup_path)
        if spec is None or spec.loader is None:
            return None
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def _try_regenerate_current_task(self, *, reason: str) -> dict | None:
        current = self._read_json_file(self.state_dir / "current_task.json")
        task = current.get("task")
        if not isinstance(task, dict):
            return None
        mechanic_id = (task.get("metadata") or {}).get("mechanic_id")
        module = self._load_setup_module()
        if module is None:
            return None
        challenge_index = int(current.get("challenge_index") or current.get("attempt") or 0) + 1
        seed = f"{reason}:{time.time_ns()}:{secrets.token_hex(12)}"
        if mechanic_id == "surreal_apple_on_tree_grid":
            public_state, ground_truth = module.generate_surreal_apple_on_tree_grid(task, seed)
        elif mechanic_id == "cursor_lens_reveal":
            public_state, ground_truth = module.generate_cursor_lens_reveal(task, seed)
        elif mechanic_id == "board_game_captcha":
            public_state, ground_truth = module.generate_board_game_captcha(task, seed)
        elif mechanic_id == "modifier_stack_image_grid":
            public_state, ground_truth = module.generate_modifier_stack_image_grid(task, seed)
        elif mechanic_id == "semantic_drag_drop_absurdity":
            public_state, ground_truth = module.generate_semantic_drag_drop_absurdity(task, seed)
        elif mechanic_id == "reload_interruption":
            public_state, ground_truth = module.generate_reload_interruption(task, seed)
        elif mechanic_id == "rotate_wrong_thing_upright":
            public_state, ground_truth = module.generate_rotate_wrong_thing_upright(task, seed)
        elif mechanic_id == "bureaucratic_signature_trap":
            public_state, ground_truth = module.generate_bureaucratic_signature_trap(task, seed)
        elif mechanic_id == "wonky_text_hostile_rendering":
            public_state, ground_truth = module.generate_wonky_text_hostile_rendering(task, seed)
        elif mechanic_id == "temporal_memory_first_change":
            public_state, ground_truth = module.generate_temporal_memory_first_change(task, seed)
        elif mechanic_id == "motion_only_ghost_jigsaw":
            public_state, ground_truth = module.generate_motion_only_ghost_jigsaw(task, seed)
        elif mechanic_id == "cursor_constellation_hunt":
            public_state, ground_truth = module.generate_cursor_constellation_hunt(task, seed)
        elif mechanic_id == "parallel_grillmaster":
            public_state, ground_truth = module.generate_parallel_grillmaster(task, seed)
        elif mechanic_id == "rotating_keyboard":
            public_state, ground_truth = module.generate_rotating_keyboard(task, seed)
        elif mechanic_id == "slot_reel_capture":
            public_state, ground_truth = module.generate_slot_reel_capture(task, seed)
        elif mechanic_id == "domino_autopsy":
            public_state, ground_truth = module.generate_domino_autopsy(task, seed)
        elif mechanic_id == "consequences_boss":
            public_state, ground_truth = module.generate_consequences_boss(task, seed)
        elif mechanic_id == "popup_exorcist":
            public_state, ground_truth = module.generate_popup_exorcist(task, seed)
        elif mechanic_id == "funeral_ritual":
            public_state, ground_truth = module.generate_funeral_ritual(task, seed)
        elif mechanic_id == "slime_commute":
            public_state, ground_truth = module.generate_slime_commute(task, seed)
        elif module.has_incubator_generator(mechanic_id):
            public_state, ground_truth = module.generate_incubator_candidate(task, seed)
        else:
            return None
        self._write_json(self.state_dir / "current_task.json", {
            "task": task,
            "seed": seed,
            "challenge_index": challenge_index,
            "last_reason": reason,
            "generated_at": time.time(),
        })
        self._write_json(self.state_dir / "public_state.json", public_state)
        self._write_json(self.state_dir / "ground_truth.json", ground_truth)
        try:
            (self.state_dir / "result.json").unlink()
        except FileNotFoundError:
            pass
        return public_state

    def _send_json(self, data: dict, status: HTTPStatus = HTTPStatus.OK) -> None:
        body = json.dumps(data, sort_keys=True).encode("utf-8")
        self.send_response(status)
        self.send_header("content-type", "application/json; charset=utf-8")
        self.send_header("cache-control", "no-store")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_static(self, path: str) -> None:
        if path in ("", "/"):
            relative = "index.html"
        else:
            relative = unquote(path).lstrip("/")
        candidate = (self.app_dir / relative).resolve()
        try:
            candidate.relative_to(self.app_dir.resolve())
        except ValueError:
            self.send_error(HTTPStatus.FORBIDDEN)
            return
        if not candidate.exists() or not candidate.is_file():
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        content_type = mimetypes.guess_type(str(candidate))[0] or "application/octet-stream"
        body = candidate.read_bytes()
        self.send_response(HTTPStatus.OK)
        self.send_header("content-type", content_type)
        self.send_header("cache-control", "no-store")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Serve Weird CAPTCHA Gym puzzle UI and state.")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8787)
    parser.add_argument("--app-dir", default="/workspace/shared_runtime/app")
    parser.add_argument("--state-dir", default="/tmp/weird_captcha_gym")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    PuzzleServer.app_dir = Path(args.app_dir)
    PuzzleServer.state_dir = Path(args.state_dir)
    PuzzleServer.state_dir.mkdir(parents=True, exist_ok=True)
    httpd = ThreadingHTTPServer((args.host, args.port), PuzzleServer)
    print(
        f"serving Weird CAPTCHA Gym app from {PuzzleServer.app_dir} "
        f"with state {PuzzleServer.state_dir} on http://{args.host}:{args.port}",
        flush=True,
    )
    httpd.serve_forever()


if __name__ == "__main__":
    main()
