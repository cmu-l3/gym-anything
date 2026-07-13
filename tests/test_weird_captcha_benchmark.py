from __future__ import annotations

import importlib.util
import json
import os
import unittest

from gym_anything.registry import (
    get_tasks_for_environment,
    list_environments,
    resolve_benchmark_root,
)


class WeirdCaptchaBenchmarkTests(unittest.TestCase):
    def test_benchmark_package_resolves_by_name(self) -> None:
        root = resolve_benchmark_root("weird_captcha_gym")
        self.assertTrue((root / "environments").is_dir())
        self.assertTrue((root / "splits").is_dir())

    def test_all_65_current_envs_are_discoverable(self) -> None:
        envs = list_environments("weird_captcha_gym", split="all")
        self.assertEqual(len(envs), 65)
        self.assertIn("reverse_identity_gate_env", envs)
        self.assertIn("temporal_memory_first_change_env", envs)
        self.assertIn("motion_only_ghost_jigsaw_env", envs)
        self.assertIn("cursor_constellation_hunt_env", envs)
        self.assertIn("parallel_grillmaster_env", envs)
        self.assertIn("rotating_keyboard_env", envs)
        self.assertIn("slot_reel_capture_env", envs)
        self.assertIn("domino_autopsy_env", envs)
        self.assertIn("consequences_boss_env", envs)
        self.assertIn("popup_exorcist_env", envs)
        self.assertIn("funeral_ritual_env", envs)
        self.assertIn("slime_commute_env", envs)
        self.assertIn("wrong_number_env", envs)
        self.assertIn("bomb_manual_from_hell_env", envs)
        self.assertIn("dead_mans_switch_env", envs)
        self.assertIn("blind_dice_courier_env", envs)
        self.assertIn("input_lag_forklift_env", envs)
        self.assertIn("insider_trading_captcha_env", envs)
        self.assertIn("polyrhythm_customs_env", envs)
        self.assertIn("exact_change_candy_cascade_env", envs)
        self.assertIn("tiny_fps_customs_env", envs)
        self.assertIn("thirty_year_time_wheel_env", envs)
        self.assertIn("shadow_crime_lab_env", envs)
        self.assertIn("craftcha_alchemy_bench_env", envs)
        self.assertIn("occlusion_shell_swindle_env", envs)
        self.assertIn("ribbon_switchboard_env", envs)
        self.assertIn("magnetic_stripe_purgatory_env", envs)
        self.assertIn("trajectory_catcher_env", envs)
        self.assertIn("impossible_panorama_env", envs)
        self.assertIn("flat_pack_compliance_env", envs)
        self.assertIn("crash_deadline_hovercar_env", envs)
        self.assertIn("robot_art_critic_env", envs)
        self.assertIn("photograph_eats_the_room_env", envs)
        self.assertIn("clockwork_doppelganger_customs_env", envs)
        self.assertIn("recursive_dollhouse_smuggling_env", envs)
        self.assertIn("flat_prisoner_env", envs)
        self.assertIn("forced_perspective_moving_day_env", envs)
        self.assertIn("lidar_blacksite_env", envs)
        self.assertIn("tomographic_baggage_surgery_env", envs)
        self.assertIn("three_camera_claw_machine_env", envs)
        self.assertIn("zero_g_cable_autopsy_env", envs)
        self.assertIn("portal_freight_oversized_parcel_env", envs)

    def test_benchmark_manifest_matches_discovered_environment_folders(self) -> None:
        benchmark_root = resolve_benchmark_root("weird_captcha_gym")
        manifest = json.loads((benchmark_root / "benchmark_manifest.json").read_text(encoding="utf-8"))
        discovered = list_environments("weird_captcha_gym", split="all")
        self.assertEqual(manifest["environment_count"], len(discovered))
        self.assertEqual(set(manifest["environments"]), set(discovered))

    def test_initial_env_task_counts_are_discoverable(self) -> None:
        for env_name in list_environments("weird_captcha_gym", split="all"):
            tasks = get_tasks_for_environment(env_name, "weird_captcha_gym", split="all")
            self.assertEqual(len(tasks), 1, env_name)
            self.assertTrue(tasks[0].endswith("_seed_0001"), tasks[0])

    def test_all_environment_and_task_hook_scripts_are_executable(self) -> None:
        benchmark_root = resolve_benchmark_root("weird_captcha_gym")
        hooks = []
        for env_name in list_environments("weird_captcha_gym", split="all"):
            env_root = benchmark_root / "environments" / env_name
            hooks.extend(env_root.glob("scripts/*.sh"))
            hooks.extend(env_root.glob("tasks/*/*.sh"))
        self.assertEqual(len(hooks), 65 * 4)
        for hook in hooks:
            self.assertTrue(os.access(hook, os.X_OK), f"hook is not executable: {hook.relative_to(benchmark_root)}")

    def test_no_tasks_are_on_verified_surface_yet(self) -> None:
        envs = list_environments("weird_captcha_gym", split="verified")
        self.assertEqual(envs, [])

    def test_interaction_first_generators_are_deterministic_and_well_formed(self) -> None:
        benchmark_root = resolve_benchmark_root("weird_captcha_gym")
        setup_path = benchmark_root / "shared_scripts" / "setup_task.py"
        spec = importlib.util.spec_from_file_location("weird_captcha_setup_task_test", setup_path)
        self.assertIsNotNone(spec)
        self.assertIsNotNone(spec.loader if spec else None)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        mechanics = {
            "motion_only_ghost_jigsaw": (module.generate_motion_only_ghost_jigsaw, 9),
            "cursor_constellation_hunt": (module.generate_cursor_constellation_hunt, 138),
            "parallel_grillmaster": (module.generate_parallel_grillmaster, 6),
            "rotating_keyboard": (module.generate_rotating_keyboard, 5),
            "slot_reel_capture": (module.generate_slot_reel_capture, 5),
        }
        for mechanic, (generator, expected_size) in mechanics.items():
            task_path = benchmark_root / "environments" / f"{mechanic}_env" / "tasks" / f"{mechanic}_seed_0001" / "task.json"
            task = json.loads(task_path.read_text(encoding="utf-8"))
            public_a, truth_a = generator(task, f"fixed-{mechanic}")
            public_b, truth_b = generator(task, f"fixed-{mechanic}")
            public_c, truth_c = generator(task, f"other-{mechanic}")
            self.assertEqual(public_a, public_b, mechanic)
            self.assertEqual(truth_a, truth_b, mechanic)
            self.assertNotEqual(truth_a["challenge_id"], truth_c["challenge_id"], mechanic)
            self.assertEqual(public_a["mechanic_id"], mechanic)
            self.assertEqual(truth_a["mechanic_id"], mechanic)
            self.assertNotIn("seed", public_a)
            if mechanic == "motion_only_ghost_jigsaw":
                self.assertEqual(len(truth_a["expected_positions"]), expected_size)
            elif mechanic == "cursor_constellation_hunt":
                self.assertEqual(len(public_a["surface"]["stars"]), expected_size)
                self.assertGreater(truth_a["expected_click"]["radius"], 0)
            elif mechanic == "parallel_grillmaster":
                self.assertEqual(len(truth_a["targets"]), expected_size)
            elif mechanic == "rotating_keyboard":
                self.assertEqual(len(truth_a["target"]), expected_size)
            else:
                self.assertEqual(len(truth_a["sequence"]), expected_size)

    def test_interaction_second_generators_are_deterministic_and_well_formed(self) -> None:
        benchmark_root = resolve_benchmark_root("weird_captcha_gym")
        setup_path = benchmark_root / "shared_scripts" / "setup_task.py"
        spec = importlib.util.spec_from_file_location("weird_captcha_setup_task_second_test", setup_path)
        self.assertIsNotNone(spec)
        self.assertIsNotNone(spec.loader if spec else None)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        mechanics = {
            "domino_autopsy": module.generate_domino_autopsy,
            "consequences_boss": module.generate_consequences_boss,
            "popup_exorcist": module.generate_popup_exorcist,
            "funeral_ritual": module.generate_funeral_ritual,
            "slime_commute": module.generate_slime_commute,
        }
        for mechanic, generator in mechanics.items():
            task_path = benchmark_root / "environments" / f"{mechanic}_env" / "tasks" / f"{mechanic}_seed_0001" / "task.json"
            task = json.loads(task_path.read_text(encoding="utf-8"))
            public_a, truth_a = generator(task, f"fixed-{mechanic}")
            public_b, truth_b = generator(task, f"fixed-{mechanic}")
            public_c, truth_c = generator(task, f"other-{mechanic}")
            self.assertEqual(public_a, public_b, mechanic)
            self.assertEqual(truth_a, truth_b, mechanic)
            self.assertNotEqual(truth_a["challenge_id"], truth_c["challenge_id"], mechanic)
            self.assertEqual(public_a["mechanic_id"], mechanic)
            self.assertEqual(truth_a["mechanic_id"], mechanic)
            self.assertNotIn("seed", public_a)
        self.assertEqual(len(mechanics["domino_autopsy"](json.loads((benchmark_root / "environments/domino_autopsy_env/tasks/domino_autopsy_seed_0001/task.json").read_text()), "shape")[1]["target_slots"]), 3)
        consequences_public, consequences_truth = mechanics["consequences_boss"](json.loads((benchmark_root / "environments/consequences_boss_env/tasks/consequences_boss_seed_0001/task.json").read_text()), "shape")
        self.assertEqual(len(consequences_public["scenes"]), 5)
        self.assertEqual(set(consequences_truth["boss_order"]), set(consequences_truth["scene_ids"]))
        self.assertEqual(len(mechanics["popup_exorcist"](json.loads((benchmark_root / "environments/popup_exorcist_env/tasks/popup_exorcist_seed_0001/task.json").read_text()), "shape")[0]["popups"]), 7)
        self.assertEqual(len(mechanics["funeral_ritual"](json.loads((benchmark_root / "environments/funeral_ritual_env/tasks/funeral_ritual_seed_0001/task.json").read_text()), "shape")[0]["flowers"]), 4)
        self.assertEqual(len(mechanics["slime_commute"](json.loads((benchmark_root / "environments/slime_commute_env/tasks/slime_commute_seed_0001/task.json").read_text()), "shape")[0]["board"]["lanes"]), 6)

    def test_interaction_second_verifiers_accept_complete_outcomes(self) -> None:
        benchmark_root = resolve_benchmark_root("weird_captcha_gym")
        setup_spec = importlib.util.spec_from_file_location("weird_captcha_setup_task_verifier_test", benchmark_root / "shared_scripts/setup_task.py")
        helper_spec = importlib.util.spec_from_file_location("weird_captcha_verifier_helpers_test", benchmark_root / "shared_runtime/verifier_helpers.py")
        self.assertIsNotNone(setup_spec and setup_spec.loader)
        self.assertIsNotNone(helper_spec and helper_spec.loader)
        setup = importlib.util.module_from_spec(setup_spec)
        helpers = importlib.util.module_from_spec(helper_spec)
        setup_spec.loader.exec_module(setup)
        helper_spec.loader.exec_module(helpers)

        def generated(mechanic, generator):
            task = json.loads((benchmark_root / f"environments/{mechanic}_env/tasks/{mechanic}_seed_0001/task.json").read_text())
            return generator(task, f"verify-{mechanic}")

        _, domino = generated("domino_autopsy", setup.generate_domino_autopsy)
        domino_chain = domino["expected_body_ids"] + [domino["bell_body_id"]]
        domino_result = {
            "placements": {domino_id: dict(slot) for domino_id, slot in zip(domino["loose_ids"], domino["target_slots"])},
            "physics_engine": "matter-js@0.20.0",
            "bell_hit": True,
            "bell_peak_angle": domino["minimum_bell_swing_radians"] + 0.01,
            "run_completed": True,
            "collision_pairs": [[left, right] for left, right in zip(domino_chain, domino_chain[1:])],
        }
        verified_domino = helpers.verify_domino_autopsy({"result": domino_result, "ground_truth": domino})
        self.assertTrue(verified_domino["passed"])
        self.assertEqual(verified_domino["score"], 100)
        domino_result["collision_pairs"].pop()
        self.assertFalse(helpers.verify_domino_autopsy({"result": domino_result, "ground_truth": domino})["passed"])

        consequence_public, consequences = generated("consequences_boss", setup.generate_consequences_boss)
        choices = {scene_id: ("left" if index % 2 == 0 else "right", index % 4) for index, scene_id in enumerate(consequences["scene_ids"])}
        consequence_events = []
        def consequence_event(kind, **details):
            consequence_events.append({"sequence": len(consequence_events) + 1, "kind": kind, **details})
        for scene_id in consequences["scene_ids"]:
            socket, seal = choices[scene_id]
            consequence_event("place", scene_id=scene_id, socket=socket)
            consequence_event("seal", scene_id=scene_id, seal=seal)
            consequence_event("commit", scene_id=scene_id, socket=socket, seal=seal)
        consequence_event("storm", duration_ms=consequences["storm_ms"])
        for scene_id in consequences["boss_order"]:
            socket, seal = choices[scene_id]
            consequence_event("reconstruct", scene_id=scene_id, socket=socket, seal=seal)
        consequence_result = {"mechanic_id": "consequences_boss", "challenge_id": consequences["challenge_id"], "events": consequence_events}
        self.assertEqual(helpers.verify_consequences_boss({"result": consequence_result, "ground_truth": consequences, "public_state": consequence_public})["score"], 100)

        popup_public, popups = generated("popup_exorcist", setup.generate_popup_exorcist)
        parasite_spec = next(item for item in popup_public["popups"] if item["id"] == popups["parasite_id"])
        well = popups["containment"]
        end = [round(float(well["x"]) + float(well["w"]) / 2 - float(parasite_spec["w"]) / 2), round(float(well["y"]) + float(well["h"]) / 2 - float(parasite_spec["h"]) / 2)]
        popup_events = [
            {"sequence": 1, "kind": "focus", "window_id": popups["parasite_id"]},
            {"sequence": 2, "kind": "close", "window_id": popups["parasite_id"]},
            {"sequence": 3, "kind": "spawn", "parent_id": popups["parasite_id"], "echo_ids": popups["echo_ids"]},
            {"sequence": 4, "kind": "focus", "window_id": popups["echo_ids"][0]},
            {"sequence": 5, "kind": "drag", "window_id": popups["echo_ids"][0], "samples": [end]},
            {"sequence": 6, "kind": "contain", "window_id": popups["echo_ids"][0]},
            {"sequence": 7, "kind": "purge", "contained_id": popups["echo_ids"][0], "remaining_before": popups["popup_ids"] + popups["echo_ids"]},
        ]
        popup_result = {"mechanic_id": "popup_exorcist", "challenge_id": popups["challenge_id"], "events": popup_events}
        self.assertEqual(helpers.verify_popup_exorcist({"result": popup_result, "ground_truth": popups, "public_state": popup_public})["score"], 100)

        _, funeral = generated("funeral_ritual", setup.generate_funeral_ritual)
        funeral_result = {"events": funeral["required_events"], "brushed_cells": list(range(funeral["brush_threshold"])), "gathered_flower_ids": funeral["flower_ids"], "completed": True}
        self.assertEqual(helpers.verify_funeral_ritual({"result": funeral_result, "ground_truth": funeral})["score"], 100)

        slime_public, slime = generated("slime_commute", setup.generate_slime_commute)
        from benchmarks.weird_captcha_gym.tools.incubator_solvers.slime_commute import _plan
        plan = _plan(slime["board"])
        slime_result = {
            "mechanic_id": "slime_commute",
            "challenge_id": slime["challenge_id"],
            "actions": [{"sequence": index, "tick": tick, "key": key} for index, (tick, key) in enumerate(plan, start=1)],
            "final_tick": plan[-1][0],
            "completed": True,
            "reason": "home",
        }
        self.assertEqual(helpers.verify_slime_commute({"result": slime_result, "ground_truth": slime, "public_state": slime_public})["score"], 100)

    def test_incubator_batch_one_plugins_are_deterministic_private_and_identity_bound(self) -> None:
        benchmark_root = resolve_benchmark_root("weird_captcha_gym")
        setup_spec = importlib.util.spec_from_file_location(
            "weird_captcha_incubator_batch_one_setup_test",
            benchmark_root / "shared_scripts" / "setup_task.py",
        )
        self.assertIsNotNone(setup_spec and setup_spec.loader)
        setup = importlib.util.module_from_spec(setup_spec)
        setup_spec.loader.exec_module(setup)
        mechanics = (
            "wrong_number",
            "bomb_manual_from_hell",
            "dead_mans_switch",
            "blind_dice_courier",
            "input_lag_forklift",
        )
        for mechanic in mechanics:
            task_path = benchmark_root / f"environments/{mechanic}_env/tasks/{mechanic}_seed_0001/task.json"
            task = json.loads(task_path.read_text(encoding="utf-8"))
            public_a, truth_a = setup.generate_incubator_candidate(task, f"fixed-{mechanic}")
            public_b, truth_b = setup.generate_incubator_candidate(task, f"fixed-{mechanic}")
            public_c, truth_c = setup.generate_incubator_candidate(task, f"other-{mechanic}")
            self.assertEqual((public_a, truth_a), (public_b, truth_b), mechanic)
            self.assertNotEqual(truth_a["challenge_id"], truth_c["challenge_id"], mechanic)
            self.assertEqual(public_a["challenge_id"], truth_a["challenge_id"], mechanic)
            self.assertEqual(public_a["mechanic_id"], mechanic)
            self.assertEqual(truth_a["mechanic_id"], mechanic)
            self.assertNotIn("seed", public_a)
            self.assertNotIn("solution", public_a)
            self.assertNotIn("solution_path", public_a)
            self.assertEqual(public_a["asset_manifest"], "shared_runtime/assets/provenance/incubator_puzzles_v1.json")

            grader_path = benchmark_root / f"shared_runtime/server/incubator_graders/{mechanic}.py"
            grader_spec = importlib.util.spec_from_file_location(f"incubator_batch_one_grader_{mechanic}", grader_path)
            self.assertIsNotNone(grader_spec and grader_spec.loader)
            grader = importlib.util.module_from_spec(grader_spec)
            grader_spec.loader.exec_module(grader)
            stale = grader.grade({"mechanic_id": mechanic, "challenge_id": "stale"}, truth_a, public_a)
            self.assertFalse(stale.get("passed"), mechanic)

        wrong_task = json.loads((benchmark_root / "environments/wrong_number_env/tasks/wrong_number_seed_0001/task.json").read_text())
        positions = set()
        for index in range(64):
            _, truth = setup.generate_incubator_candidate(wrong_task, f"position-audit-{index}")
            positions.add(int(truth["target_slot"]))
        self.assertEqual(positions, set(range(7)))

    def test_incubator_batch_two_plugins_are_deterministic_private_and_identity_bound(self) -> None:
        benchmark_root = resolve_benchmark_root("weird_captcha_gym")
        setup_spec = importlib.util.spec_from_file_location(
            "weird_captcha_incubator_batch_two_setup_test",
            benchmark_root / "shared_scripts" / "setup_task.py",
        )
        self.assertIsNotNone(setup_spec and setup_spec.loader)
        setup = importlib.util.module_from_spec(setup_spec)
        setup_spec.loader.exec_module(setup)
        mechanics = (
            "insider_trading_captcha",
            "polyrhythm_customs",
            "exact_change_candy_cascade",
            "tiny_fps_customs",
            "thirty_year_time_wheel",
        )
        generated: dict[str, tuple[dict, dict]] = {}
        for mechanic in mechanics:
            task_path = benchmark_root / f"environments/{mechanic}_env/tasks/{mechanic}_seed_0001/task.json"
            task = json.loads(task_path.read_text(encoding="utf-8"))
            public_a, truth_a = setup.generate_incubator_candidate(task, f"fixed-{mechanic}")
            public_b, truth_b = setup.generate_incubator_candidate(task, f"fixed-{mechanic}")
            public_c, truth_c = setup.generate_incubator_candidate(task, f"other-{mechanic}")
            self.assertEqual((public_a, truth_a), (public_b, truth_b), mechanic)
            self.assertNotEqual(truth_a["challenge_id"], truth_c["challenge_id"], mechanic)
            self.assertEqual(public_a["challenge_id"], truth_a["challenge_id"], mechanic)
            self.assertEqual(public_a["mechanic_id"], mechanic)
            self.assertEqual(truth_a["mechanic_id"], mechanic)
            self.assertNotIn("seed", public_a)
            self.assertFalse(any("solution" in key or "solver" in key for key in public_a), mechanic)
            self.assertEqual(public_a["asset_manifest"], "shared_runtime/assets/provenance/incubator_puzzles_v1.json")

            grader_path = benchmark_root / f"shared_runtime/server/incubator_graders/{mechanic}.py"
            grader_spec = importlib.util.spec_from_file_location(f"incubator_batch_two_grader_{mechanic}", grader_path)
            self.assertIsNotNone(grader_spec and grader_spec.loader)
            grader = importlib.util.module_from_spec(grader_spec)
            grader_spec.loader.exec_module(grader)
            stale = grader.grade({"mechanic_id": mechanic, "challenge_id": "stale"}, truth_a, public_a)
            self.assertFalse(stale.get("passed"), mechanic)
            generated[mechanic] = (public_a, truth_a)

        _, candy_truth = generated["exact_change_candy_cascade"]
        self.assertEqual(len(candy_truth["solution_swaps"]), 2)
        self.assertGreaterEqual(max(candy_truth["solution_wave_counts"]), 2)
        _, rhythm_truth = generated["polyrhythm_customs"]
        self.assertTrue(rhythm_truth["chords"])
        self.assertTrue(any(note["kind"] == "hold" and note["duration_ms"] > 0 for note in rhythm_truth["expected_notes"]))

        fps_task = json.loads((benchmark_root / "environments/tiny_fps_customs_env/tasks/tiny_fps_customs_seed_0001/task.json").read_text())
        fps_layouts = {
            setup.generate_incubator_candidate(fps_task, f"layout-audit-{index}")[0]["layout_variant"]
            for index in range(32)
        }
        self.assertEqual(fps_layouts, {"identity", "mirror_x", "mirror_y", "rotate_180"})

    def test_next_ten_v3_generators_have_meaningful_structural_variation_and_scale(self) -> None:
        benchmark_root = resolve_benchmark_root("weird_captcha_gym")
        setup_spec = importlib.util.spec_from_file_location(
            "weird_captcha_next_ten_v3_generator_audit",
            benchmark_root / "shared_scripts" / "setup_task.py",
        )
        self.assertIsNotNone(setup_spec and setup_spec.loader)
        setup = importlib.util.module_from_spec(setup_spec)
        setup_spec.loader.exec_module(setup)
        mechanics = (
            "impossible_panorama",
            "flat_pack_compliance",
            "crash_deadline_hovercar",
            "robot_art_critic",
            "wrong_number",
            "bomb_manual_from_hell",
            "dead_mans_switch",
            "blind_dice_courier",
            "input_lag_forklift",
            "insider_trading_captcha",
        )
        generated: dict[str, list[dict]] = {}
        examples: dict[str, tuple[dict, dict]] = {}
        for mechanic in mechanics:
            task_path = benchmark_root / f"environments/{mechanic}_env/tasks/{mechanic}_seed_0001/task.json"
            task = json.loads(task_path.read_text(encoding="utf-8"))
            challenge_ids: set[str] = set()
            contracts: set[str] = set()
            truths: list[dict] = []
            for index in range(80):
                public, truth = setup.generate_incubator_candidate(
                    task, f"next-ten-v3-generator-{mechanic}-{index}"
                )
                challenge_ids.add(str(truth["challenge_id"]))
                core = {
                    key: value
                    for key, value in truth.items()
                    if key not in {"seed", "challenge_id"}
                }
                contracts.add(json.dumps(core, sort_keys=True, separators=(",", ":")))
                self.assertEqual(public["challenge_id"], truth["challenge_id"])
                self.assertNotIn("seed", public)
                self.assertFalse(
                    any("solution" in key or "solver" in key for key in public),
                    mechanic,
                )
                if index == 0:
                    examples[mechanic] = (public, truth)
                truths.append(truth)
            self.assertEqual(len(challenge_ids), 80, mechanic)
            self.assertGreaterEqual(len(contracts), 40, mechanic)
            generated[mechanic] = truths

        for mechanic, (public, truth) in examples.items():
            grader_path = benchmark_root / f"shared_runtime/server/incubator_graders/{mechanic}.py"
            grader_spec = importlib.util.spec_from_file_location(
                f"next_ten_v3_task_binding_{mechanic}", grader_path
            )
            self.assertIsNotNone(grader_spec and grader_spec.loader)
            grader = importlib.util.module_from_spec(grader_spec)
            grader_spec.loader.exec_module(grader)
            mismatch = grader.grade(
                {
                    "mechanic_id": mechanic,
                    "task_id": "tampered-task",
                    "challenge_id": truth["challenge_id"],
                },
                truth,
                public,
            )
            self.assertFalse(mismatch.get("passed"), mechanic)
            self.assertIn("task", str(mismatch.get("feedback") or "").lower(), mechanic)

            forged_terminal_claim = grader.grade(
                {
                    "mechanic_id": mechanic,
                    "task_id": truth["task_id"],
                    "challenge_id": truth["challenge_id"],
                    "passed": True,
                    "score": 100,
                    "events": [],
                },
                truth,
                public,
            )
            self.assertFalse(
                forged_terminal_claim.get("passed"),
                f"{mechanic} trusted a client PASS without a replayable interaction transcript",
            )

        self.assertEqual(
            {int(truth["target_slot"]) for truth in generated["wrong_number"]},
            set(range(7)),
        )
        self.assertEqual(
            {int(truth["correct_wire_index"]) for truth in generated["bomb_manual_from_hell"]},
            set(range(9)),
        )
        forklift_truths = generated["input_lag_forklift"]
        self.assertEqual({int(truth["layout_index"]) for truth in forklift_truths}, set(range(12)))
        self.assertEqual(
            {str(truth["transform"]) for truth in forklift_truths},
            {"identity", "mirror_x", "mirror_y", "rotate_180"},
        )
        self.assertEqual(
            {str(truth["palette"]) for truth in forklift_truths},
            {"amber", "oxide", "mint", "cobalt"},
        )
        self.assertTrue(
            all(
                "max_pointer_jump" not in (truth.get("requirements") or {})
                for truth in generated["crash_deadline_hovercar"]
            ),
            "hovercar correctness must not depend on VNC pointer event density",
        )
        self.assertTrue(all(len(truth["objects"]) == 32 and truth["world"]["sector_columns"] == 8 and truth["world"]["sector_rows"] == 4 for truth in generated["impossible_panorama"]))
        self.assertTrue(all(len(truth["parts"]) == 7 and len(truth["joints"]) == 6 and len(truth["load_steps"]) == 36 for truth in generated["flat_pack_compliance"]))
        self.assertTrue(all(len(truth["targets"]) == 5 and len(truth["obstacles"]) == 6 for truth in generated["crash_deadline_hovercar"]))
        self.assertTrue(all(int(truth["target"]["expected_strokes"]) >= 10 and len(truth["class_vocabulary"]) == 8 for truth in generated["robot_art_critic"]))
        self.assertTrue(all(len(truth["lines"]) == 7 and int(truth["qualification"]["trial_ms"]) >= 4_800 and min(abs(int(line["drift_milli_steps_per_second"])) for line in truth["lines"]) >= 1_180 for truth in generated["wrong_number"]))
        self.assertTrue(all(len(truth["plates"]) == 5 and len(truth["wires"]) == 9 and all(len(plate["apertures"]) == 5 for plate in truth["plates"]) for truth in generated["bomb_manual_from_hell"]))
        self.assertTrue(all(len(truth["board"]["checkpoints"]) == 5 and int(truth["minimum_success_moves"]) >= 42 and int(truth["pressure_motion"]["minimum_hold_ms"]) >= 5_200 for truth in generated["dead_mans_switch"]))
        self.assertTrue(all(len(truth["board"]["gates"]) == 5 and len(truth["solution_path"]) >= 48 for truth in generated["blind_dice_courier"]))
        self.assertTrue(all(len(truth["initial_state"]["crates"]) == 2 and len(truth["solution"]) >= 22 for truth in generated["input_lag_forklift"]))
        self.assertTrue(
            all(
                len(truth["prices_cents"]) >= 34
                and int(truth["order_delay_ticks"]) >= 3
                and int(truth["causal_reference_profit_cents"]) >= 1_400
                and len(truth["causal_reference_ledger"]) >= 10
                and int(truth["target_profit_cents"]) >= 1_100
                and int(truth["causal_reference_profit_cents"])
                >= int(truth["target_profit_cents"])
                for truth in generated["insider_trading_captcha"]
            )
        )
        for truth in generated["insider_trading_captcha"]:
            prices = [int(value) for value in truth["prices_cents"]]
            deltas = [right - left for left, right in zip(prices, prices[1:])]
            nonzero_signs = [1 if value > 0 else -1 for value in deltas if value]
            self.assertGreaterEqual(
                sum(left != right for left, right in zip(nonzero_signs, nonzero_signs[1:])),
                3,
            )
            for lag in range(2, min(13, len(deltas) // 2)):
                near_repeats = sum(
                    abs(deltas[index] - deltas[index - lag]) <= 10
                    for index in range(lag, len(deltas))
                )
                self.assertLess(
                    near_repeats / (len(deltas) - lag),
                    0.45,
                    f"market tape retained a short near-period at lag {lag}",
                )

    def test_every_incubator_plugin_has_a_complete_identity_bound_surface(self) -> None:
        benchmark_root = resolve_benchmark_root("weird_captcha_gym")
        setup_spec = importlib.util.spec_from_file_location(
            "weird_captcha_all_incubator_plugins_setup_test",
            benchmark_root / "shared_scripts" / "setup_task.py",
        )
        self.assertIsNotNone(setup_spec and setup_spec.loader)
        setup = importlib.util.module_from_spec(setup_spec)
        setup_spec.loader.exec_module(setup)
        generator_root = benchmark_root / "shared_scripts" / "incubator_generators"
        mechanics = sorted(path.stem for path in generator_root.glob("*.py") if not path.name.startswith("_"))
        self.assertGreaterEqual(len(mechanics), 10)
        for mechanic in mechanics:
            env_root = benchmark_root / "environments" / f"{mechanic}_env"
            task_root = env_root / "tasks" / f"{mechanic}_seed_0001"
            task_path = task_root / "task.json"
            grader_path = benchmark_root / "shared_runtime" / "server" / "incubator_graders" / f"{mechanic}.py"
            frontend_root = benchmark_root / "shared_runtime" / "app" / "mechanics"
            solver_path = benchmark_root / "tools" / "incubator_solvers" / f"{mechanic}.py"
            split_path = benchmark_root / "splits" / f"{mechanic}_split.json"
            for required in (
                env_root / "env.json",
                task_path,
                task_root / "verifier.py",
                grader_path,
                frontend_root / f"{mechanic}.js",
                frontend_root / f"{mechanic}.css",
                solver_path,
                split_path,
            ):
                self.assertTrue(required.is_file(), f"{mechanic}: missing {required.relative_to(benchmark_root)}")

            task = json.loads(task_path.read_text(encoding="utf-8"))
            self.assertEqual(task["metadata"]["status"], "prototype_visual_candidate", mechanic)
            public_a, truth_a = setup.generate_incubator_candidate(task, f"surface-{mechanic}")
            public_b, truth_b = setup.generate_incubator_candidate(task, f"surface-{mechanic}")
            public_c, truth_c = setup.generate_incubator_candidate(task, f"surface-other-{mechanic}")
            self.assertEqual((public_a, truth_a), (public_b, truth_b), mechanic)
            self.assertNotEqual(truth_a["challenge_id"], truth_c["challenge_id"], mechanic)
            self.assertEqual(public_a["challenge_id"], truth_a["challenge_id"], mechanic)
            self.assertEqual(public_a["mechanic_id"], mechanic)
            self.assertEqual(truth_a["mechanic_id"], mechanic)
            self.assertNotIn("seed", public_a)
            asset_manifest = benchmark_root / str(public_a["asset_manifest"])
            self.assertTrue(asset_manifest.is_file(), f"{mechanic}: missing asset manifest")

            grader_spec = importlib.util.spec_from_file_location(f"all_incubator_grader_{mechanic}", grader_path)
            self.assertIsNotNone(grader_spec and grader_spec.loader)
            grader = importlib.util.module_from_spec(grader_spec)
            grader_spec.loader.exec_module(grader)
            stale = grader.grade({"mechanic_id": mechanic, "challenge_id": "stale"}, truth_a, public_a)
            self.assertFalse(stale.get("passed"), mechanic)


if __name__ == "__main__":
    unittest.main()
