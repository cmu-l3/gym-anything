from __future__ import annotations

import json
import subprocess
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.request
from collections import Counter
from pathlib import Path
from unittest import mock

from benchmarks.weird_captcha_gym.dashboard.catalog import BENCHMARK_ROOT, REPO_ROOT, build_catalog
from benchmarks.weird_captcha_gym.dashboard.atlas import (
    AtlasCurationStore, COLLECTION_ROOT, artifact_page, build_atlas, instance_detail, instance_page,
    source_detail, specimen_detail,
)
from benchmarks.weird_captcha_gym.dashboard.server import DashboardServer, EvaluationManager, SessionManager
from benchmarks.weird_captcha_gym.dashboard.export_static import _validate_output_path, export_dashboard
from benchmarks.weird_captcha_gym.dashboard.reviews import EnvironmentReviewStore


PACK_III = {
    "shadow_crime_lab", "craftcha_alchemy_bench", "occlusion_shell_swindle",
    "ribbon_switchboard", "magnetic_stripe_purgatory",
}
PACK_IV = {
    "trajectory_catcher", "impossible_panorama", "flat_pack_compliance",
    "crash_deadline_hovercar", "robot_art_critic",
}
PACK_V = {
    "photograph_eats_the_room", "clockwork_doppelganger_customs",
    "recursive_dollhouse_smuggling", "flat_prisoner",
    "forced_perspective_moving_day",
}
PACK_VI = {
    "lidar_blacksite", "tomographic_baggage_surgery",
    "three_camera_claw_machine", "zero_g_cable_autopsy",
    "portal_freight_oversized_parcel",
}
SURVEY_CORPUS_AVAILABLE = (
    (COLLECTION_ROOT / "catalog.jsonl").is_file()
    and (COLLECTION_ROOT / "mechanic-index.jsonl").is_file()
    and (COLLECTION_ROOT / "sources").is_dir()
)
SURVEY_SKIP_REASON = "optional sibling research/collection survey corpus is not present"


class WeirdCaptchaDashboardTests(unittest.TestCase):
    def test_environment_review_ledger_is_atomic_persistent_and_built_only(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "environment-reviews.json"
            store = EnvironmentReviewStore(path)
            self.assertEqual(store.snapshot()["stats"], {
                "total": 63,
                "reviewed": 0,
                "decided": 0,
                "pending": 63,
                "hands_on_pending": 63,
                "looks_good": 0,
                "approved": 0,
                "revision_requested": 0,
            })
            approved = store.update("domino_autopsy_env", {"status": "approved", "note": "Bell and chain feel fair."})
            self.assertEqual(approved["status"], "approved")
            self.assertEqual(len(approved["history"]), 1)
            revised = store.update("domino_autopsy_env", {"status": "revision_requested", "note": "Make the bell strike more legible."})
            self.assertEqual(revised["status"], "revision_requested")
            self.assertEqual(len(revised["history"]), 2)
            reloaded = EnvironmentReviewStore(path).snapshot()
            self.assertEqual(reloaded["stats"]["revision_requested"], 1)
            self.assertEqual(reloaded["stats"]["pending"], 62)
            self.assertEqual(reloaded["items"]["domino_autopsy_env"]["note"], "Make the bell strike more legible.")
            screened = store.update("domino_autopsy_env", {"status": "looks_good", "note": "Film looks good; VNC still pending."})
            self.assertEqual(screened["status"], "looks_good")
            self.assertEqual(len(screened["history"]), 3)
            screened_snapshot = EnvironmentReviewStore(path).snapshot()
            self.assertEqual(screened_snapshot["stats"]["looks_good"], 1)
            self.assertEqual(screened_snapshot["stats"]["decided"], 0)
            self.assertEqual(screened_snapshot["stats"]["reviewed"], 1)
            self.assertEqual(screened_snapshot["stats"]["hands_on_pending"], 63)
            with self.assertRaisesRegex(ValueError, "require a note"):
                store.update("domino_autopsy_env", {"status": "revision_requested", "note": ""})
            archived = next(environment["id"] for environment in build_catalog()["environments"] if environment["stage"] == "rejected")
            with self.assertRaisesRegex(ValueError, "non-reviewable"):
                store.update(archived, {"status": "approved", "note": ""})

    @unittest.skipUnless(SURVEY_CORPUS_AVAILABLE, SURVEY_SKIP_REASON)
    def test_atlas_ingests_individual_specimens_sources_and_real_artifacts(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            store = AtlasCurationStore(Path(temporary) / "curation.json")
            atlas = build_atlas(store)
        self.assertTrue(atlas["available"])
        self.assertEqual(atlas["stats"]["designs"], 44)
        self.assertEqual(atlas["stats"]["variants"], 250)
        self.assertEqual(atlas["stats"]["instances"], 1_043)
        self.assertEqual(atlas["stats"]["ground_truth_instances"], 983)
        self.assertEqual(atlas["stats"]["captured_examples"], 60)
        self.assertEqual(atlas["stats"]["catalog_records"], 1_411)
        self.assertEqual(atlas["stats"]["specimens"], 294)  # compatibility: designs + variants
        self.assertEqual(atlas["stats"]["sources"], 74)
        self.assertEqual(atlas["stats"]["files"], 19_168)
        self.assertEqual(atlas["stats"]["media"], 1_788)
        self.assertEqual(atlas["stats"]["visual_assets"], 12_710)
        self.assertEqual(atlas["stats"]["indexed_mechanics"], 44)
        specimen_types = Counter(specimen["specimen_type"] for specimen in atlas["specimens"])
        self.assertEqual(specimen_types["indexed_mechanic"], 44)
        self.assertEqual(specimen_types["verified_generator"], 28)
        self.assertEqual(specimen_types["extracted_game_screen"], 16)
        self.assertEqual(specimen_types["source_component"], 14)
        self.assertEqual(len(atlas["instance_sources"]), 3)
        self.assertEqual(len(atlas["instance_families"]), 52)

    @unittest.skipUnless(SURVEY_CORPUS_AVAILABLE, SURVEY_SKIP_REASON)
    def test_atlas_details_preserve_item_level_evidence_and_source_notes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            store = AtlasCurationStore(Path(temporary) / "curation.json")
            slot_machine = specimen_detail("neal-im-not-a-robot--level-40", store)
            self.assertEqual(slot_machine["title"], "Slot Machine")
            self.assertTrue(any("level-40" in artifact["path"] for artifact in slot_machine["artifacts"]))
            captured = specimen_detail("captcha-rpg--state-01", store)
            self.assertTrue(any("01-levelOneVerifyButton.png" in artifact["path"] for artifact in captured["artifacts"]))
            dossier = source_detail("captcha-rpg", store)
            self.assertIn("Captcha RPG", dossier["notes"])
            self.assertEqual(len(dossier["specimens"]), 50)
            images = artifact_page("nextgen-captchas-benchmark", kind="image", limit=12)
            self.assertEqual(len(images["artifacts"]), 12)
            self.assertTrue(images["has_more"])
            self.assertTrue(all(artifact["kind"] == "image" for artifact in images["artifacts"]))
            page = instance_page(source="nextgen-captchas-benchmark", family="3D_Viewpoint", limit=2, store=store)
            self.assertEqual(page["total"], 20)
            self.assertEqual(len(page["instances"]), 2)
            concrete = instance_detail(page["instances"][0]["id"], store)
            self.assertEqual(concrete["ground_truth_status"], "recorded")
            self.assertEqual(len(concrete["assets"]), 10)
            self.assertIn("answer", concrete["ground_truth"])
            virc = instance_page(source="visual-reasoning-captcha-vtt", limit=1, store=store)
            self.assertEqual(virc["total"], 60)
            self.assertEqual(virc["instances"][0]["ground_truth_status"], "unavailable")

    @unittest.skipUnless(SURVEY_CORPUS_AVAILABLE, SURVEY_SKIP_REASON)
    def test_atlas_curation_is_persistent_without_fabricating_an_environment(self) -> None:
        before = build_catalog()["stats"]["total"]
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "atlas-curation.json"
            store = AtlasCurationStore(path)
            saved = store.update("neal-im-not-a-robot--level-40", {"decision": "maybe", "note": "Timing is the actual task."})
            self.assertEqual(saved["decision"], "maybe")
            promoted = store.update("neal-im-not-a-robot--level-40", {"decision": "maybe", "note": saved["note"], "promoted": True})
            self.assertEqual(promoted["decision"], "shortlisted")
            self.assertTrue(promoted["promoted"])
            reloaded = build_atlas(AtlasCurationStore(path))
            specimen = next(item for item in reloaded["specimens"] if item["id"] == "neal-im-not-a-robot--level-40")
            self.assertEqual(specimen["curation"]["note"], "Timing is the actual task.")
            self.assertTrue(specimen["curation"]["promoted"])
            self.assertEqual(reloaded["stats"]["promoted"], 1)
            concrete_id = instance_page(limit=1, store=store)["instances"][0]["id"]
            store.update(concrete_id, {"decision": "shortlisted", "note": "concrete seed"})
            self.assertEqual(instance_detail(concrete_id, store)["curation"]["note"], "concrete seed")
        self.assertEqual(build_catalog()["stats"]["total"], before)

    @unittest.skipIf(SURVEY_CORPUS_AVAILABLE, "full sibling survey corpus is present")
    def test_atlas_gracefully_reports_an_absent_optional_survey_corpus(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            atlas = build_atlas(AtlasCurationStore(Path(temporary) / "curation.json"))
        self.assertFalse(atlas["available"])
        self.assertEqual(atlas["stats"]["catalog_records"], 0)
        self.assertEqual(atlas["stats"]["files"], 0)

    def test_catalog_reports_the_final_environment_inventory(self) -> None:
        catalog = build_catalog()
        self.assertEqual(catalog["stats"]["total"], 65)
        self.assertEqual(catalog["stats"]["built"], 63)
        self.assertEqual(catalog["stats"]["browser_verified"], 63)
        self.assertEqual(catalog["stats"]["scaffolds"], 0)
        self.assertEqual(catalog["stats"]["concepts"], 0)
        self.assertEqual(catalog["stats"]["incubator_candidates"], 0)
        self.assertEqual(catalog["stats"]["human_touched"], 6)
        self.assertEqual(catalog["stats"]["solution_videos"], 11)
        self.assertEqual(sum(group["count"] for group in catalog["groups"]), 65)
        recordings = [environment for environment in catalog["environments"] if environment["solution_video"]]
        self.assertEqual(len(recordings), 11)
        for environment in recordings:
            video = environment["solution_video"]
            self.assertTrue(video["verified"], environment["mechanic_id"])
            self.assertEqual((video["width"], video["height"]), (1280, 720))
        current_recordings = [environment for environment in recordings if environment["mechanic_id"] != "semantic_drag_drop_absurdity"]
        self.assertEqual(len(current_recordings), 10)
        for environment in current_recordings:
            self.assertIn("/media/evidence/next_ten_difficulty_v3/solution_videos/", environment["solution_video"]["mp4_url"])
            self.assertTrue(environment["solution_video"]["frozen_contract_verified"])
        semantic = next(environment for environment in recordings if environment["mechanic_id"] == "semantic_drag_drop_absurdity")
        self.assertTrue(semantic["solution_video"]["mp4_url"].endswith("/reviewed_overhaul_v1/semantic_drag_drop_absurdity-walkthrough.mp4"))
        self.assertTrue(semantic["solution_video"]["webm_url"].endswith("/reviewed_overhaul_v1/semantic_drag_drop_absurdity-walkthrough.webm"))
        self.assertEqual(semantic["solution_video"]["duration_seconds"], 60.2)
        self.assertFalse(semantic["solution_video"]["frozen_contract_verified"])
        critic = next(environment for environment in catalog["environments"] if environment["mechanic_id"] == "robot_art_critic")
        self.assertIn("fixed prototype family", critic["known_limitations"][0])

    def test_all_twenty_selected_pack_three_through_six_designs_are_promoted(self) -> None:
        selected = PACK_III | PACK_IV | PACK_V | PACK_VI
        environments = {
            environment["mechanic_id"]: environment
            for environment in build_catalog()["environments"]
            if environment["mechanic_id"] in selected
        }
        self.assertEqual(set(environments), selected)
        self.assertEqual(Counter(environment["group"] for environment in environments.values()), {
            "Interaction III": 5,
            "Interaction IV": 5,
            "Interaction V": 5,
            "Interaction VI": 5,
        })
        for mechanic, environment in environments.items():
            self.assertEqual(environment["stage"], "built", mechanic)
            self.assertTrue(environment["launchable"], mechanic)
            self.assertTrue(environment["tasks"], mechanic)
            self.assertTrue(environment["screenshots"], mechanic)
            self.assertTrue(environment["validation"]["ok"], mechanic)
            self.assertTrue(environment["source_anchors"], mechanic)
            self.assertEqual(environment["design_status"], "local_verification_pending_vnc_human_evidence", mechanic)

    def test_incubator_queue_has_been_promoted_to_real_environments(self) -> None:
        candidates = [environment for environment in build_catalog()["environments"] if environment["stage"] == "incubator"]
        self.assertEqual(candidates, [])
        expected = {
            "wrong_number",
            "bomb_manual_from_hell",
            "dead_mans_switch",
            "blind_dice_courier",
            "input_lag_forklift",
            "insider_trading_captcha",
            "polyrhythm_customs",
            "exact_change_candy_cascade",
            "tiny_fps_customs",
            "thirty_year_time_wheel",
        }
        promoted = [
            environment
            for environment in build_catalog()["environments"]
            if environment["mechanic_id"] in expected
        ]
        self.assertEqual(
            {environment["mechanic_id"] for environment in promoted},
            expected,
        )
        for environment in promoted:
            self.assertEqual(environment["group"], "Incubator")
            self.assertEqual(environment["stage"], "built")
            self.assertTrue(environment["launchable"])
            self.assertTrue(environment["tasks"])
            self.assertTrue(environment["screenshots"])
            self.assertTrue(environment["source_anchors"])

    def test_incubator_batch_one_is_launchable_but_still_pending_human_vnc_evidence(self) -> None:
        expected = {
            "wrong_number",
            "bomb_manual_from_hell",
            "dead_mans_switch",
            "blind_dice_courier",
            "input_lag_forklift",
        }
        environments = {
            environment["mechanic_id"]: environment
            for environment in build_catalog()["environments"]
            if environment["mechanic_id"] in expected
        }
        self.assertEqual(set(environments), expected)
        for mechanic, environment in environments.items():
            self.assertEqual(environment["stage"], "built", mechanic)
            self.assertTrue(environment["launchable"], mechanic)
            self.assertTrue(environment["screenshots"], mechanic)
            self.assertTrue(environment["validation"]["ok"], mechanic)
            self.assertEqual(environment["design_status"], "local_verification_pending_vnc_human_evidence")

    def test_incubator_batch_two_is_launchable_but_still_pending_human_vnc_evidence(self) -> None:
        expected = {
            "insider_trading_captcha",
            "polyrhythm_customs",
            "exact_change_candy_cascade",
            "tiny_fps_customs",
            "thirty_year_time_wheel",
        }
        environments = {
            environment["mechanic_id"]: environment
            for environment in build_catalog()["environments"]
            if environment["mechanic_id"] in expected
        }
        self.assertEqual(set(environments), expected)
        for mechanic, environment in environments.items():
            self.assertEqual(environment["stage"], "built", mechanic)
            self.assertTrue(environment["launchable"], mechanic)
            self.assertTrue(environment["screenshots"], mechanic)
            self.assertTrue(environment["validation"]["ok"], mechanic)
            self.assertEqual(environment["design_status"], "local_verification_pending_vnc_human_evidence")

    def test_historical_incubator_batch_three_is_launchable_with_evidence(self) -> None:
        expected = {
            "code_to_diagram_captcha",
            "exit_vim_terminal_escape",
            "fake_desktop_automation_inversion",
            "impossible_ecology",
            "jigsaw_slider_alignment",
        }
        environments = {
            environment["mechanic_id"]: environment
            for environment in build_catalog()["environments"]
            if environment["mechanic_id"] in expected
        }
        self.assertEqual(set(environments), expected)
        for mechanic, environment in environments.items():
            self.assertEqual(environment["stage"], "built", mechanic)
            self.assertTrue(environment["launchable"], mechanic)
            self.assertTrue(environment["screenshots"], mechanic)
            self.assertTrue(environment["validation"]["ok"], mechanic)
            self.assertEqual(environment["design_status"], "local_verification_pending_vnc_human_evidence")

    def test_historical_incubator_batch_four_is_launchable_with_evidence(self) -> None:
        expected = {
            "microgame_gauntlet",
            "minecraft_block_grid",
            "relation_prompt_grounding",
            "rorschach_fixed_rubric",
            "single_scene_split_boxes",
        }
        environments = {
            environment["mechanic_id"]: environment
            for environment in build_catalog()["environments"]
            if environment["mechanic_id"] in expected
        }
        self.assertEqual(set(environments), expected)
        for mechanic, environment in environments.items():
            self.assertEqual(environment["stage"], "built", mechanic)
            self.assertTrue(environment["launchable"], mechanic)
            self.assertTrue(environment["screenshots"], mechanic)
            self.assertTrue(environment["validation"]["ok"], mechanic)
            self.assertEqual(environment["design_status"], "local_verification_pending_vnc_human_evidence")

    def test_historical_incubator_batch_five_is_launchable_with_evidence(self) -> None:
        expected = {
            "top_face_dice_arithmetic",
            "trace_shape_without_walls",
            "wizard_critter_capture",
        }
        environments = {
            environment["mechanic_id"]: environment
            for environment in build_catalog()["environments"]
            if environment["mechanic_id"] in expected
        }
        self.assertEqual(set(environments), expected)
        for mechanic, environment in environments.items():
            self.assertEqual(environment["stage"], "built", mechanic)
            self.assertTrue(environment["launchable"], mechanic)
            self.assertTrue(environment["screenshots"], mechanic)
            self.assertTrue(environment["validation"]["ok"], mechanic)
            self.assertEqual(environment["design_status"], "local_verification_pending_vnc_human_evidence")

    def test_interaction_three_batch_six_is_launchable_with_evidence(self) -> None:
        expected = {
            "shadow_crime_lab",
            "craftcha_alchemy_bench",
            "occlusion_shell_swindle",
            "ribbon_switchboard",
            "magnetic_stripe_purgatory",
        }
        environments = {
            environment["mechanic_id"]: environment
            for environment in build_catalog()["environments"]
            if environment["mechanic_id"] in expected
        }
        self.assertEqual(set(environments), expected)
        for mechanic, environment in environments.items():
            self.assertEqual(environment["group"], "Interaction III", mechanic)
            self.assertEqual(environment["stage"], "built", mechanic)
            self.assertTrue(environment["launchable"], mechanic)
            self.assertTrue(environment["screenshots"], mechanic)
            self.assertTrue(environment["validation"]["ok"], mechanic)
            self.assertEqual(environment["design_status"], "local_verification_pending_vnc_human_evidence")

    def test_interaction_four_batch_seven_is_launchable_with_evidence(self) -> None:
        expected = {
            "trajectory_catcher",
            "impossible_panorama",
            "flat_pack_compliance",
            "crash_deadline_hovercar",
            "robot_art_critic",
        }
        environments = {
            environment["mechanic_id"]: environment
            for environment in build_catalog()["environments"]
            if environment["mechanic_id"] in expected
        }
        self.assertEqual(set(environments), expected)
        for mechanic, environment in environments.items():
            self.assertEqual(environment["group"], "Interaction IV", mechanic)
            self.assertEqual(environment["stage"], "built", mechanic)
            self.assertTrue(environment["launchable"], mechanic)
            self.assertTrue(environment["screenshots"], mechanic)
            self.assertTrue(environment["validation"]["ok"], mechanic)
            self.assertEqual(environment["design_status"], "local_verification_pending_vnc_human_evidence")

    def test_interaction_five_batch_eight_is_launchable_with_independent_evidence(self) -> None:
        environments = {
            environment["mechanic_id"]: environment
            for environment in build_catalog()["environments"]
            if environment["mechanic_id"] in PACK_V
        }
        self.assertEqual(set(environments), PACK_V)
        for mechanic, environment in environments.items():
            self.assertEqual(environment["group"], "Interaction V", mechanic)
            self.assertEqual(environment["stage"], "built", mechanic)
            self.assertTrue(environment["launchable"], mechanic)
            self.assertTrue(environment["screenshots"], mechanic)
            self.assertTrue(environment["validation"]["ok"], mechanic)
            self.assertEqual(environment["design_status"], "local_verification_pending_vnc_human_evidence")

        summary = json.loads((BENCHMARK_ROOT / "evidence/incubator_batch_eight_v1/summary.json").read_text(encoding="utf-8"))
        self.assertTrue(summary["ok"])
        self.assertEqual(set(summary["mechanics"]), PACK_V)
        self.assertEqual(sum(len(result["screenshots"]) for result in summary["mechanics"].values()), 46)
        for mechanic, result in summary["mechanics"].items():
            self.assertTrue(result["ok"], mechanic)
            self.assertTrue(result["server_grade"]["passed"], mechanic)
            self.assertTrue(result["direct_grade"]["passed"], mechanic)
            self.assertTrue(result["verifier"]["passed"], mechanic)
    def test_interaction_six_batch_nine_is_launchable_with_independent_evidence(self) -> None:
        environments = {
            environment["mechanic_id"]: environment
            for environment in build_catalog()["environments"]
            if environment["mechanic_id"] in PACK_VI
        }
        self.assertEqual(set(environments), PACK_VI)
        for mechanic, environment in environments.items():
            self.assertEqual(environment["group"], "Interaction VI", mechanic)
            self.assertEqual(environment["stage"], "built", mechanic)
            self.assertTrue(environment["launchable"], mechanic)
            self.assertTrue(environment["screenshots"], mechanic)
            self.assertTrue(environment["validation"]["ok"], mechanic)
            self.assertEqual(environment["design_status"], "local_verification_pending_vnc_human_evidence")

        summary = json.loads((BENCHMARK_ROOT / "evidence/incubator_batch_nine_v1/summary.json").read_text(encoding="utf-8"))
        self.assertTrue(summary["ok"])
        self.assertEqual(set(summary["mechanics"]), PACK_VI)
        self.assertEqual(sum(len(result["screenshots"]) for result in summary["mechanics"].values()), 47)
        for mechanic, result in summary["mechanics"].items():
            self.assertTrue(result["ok"], mechanic)
            self.assertTrue(result["server_grade"]["passed"], mechanic)
            self.assertTrue(result["direct_grade"]["passed"], mechanic)
            self.assertTrue(result["verifier"]["passed"], mechanic)
        clean_acceptance = {
            "lidar_blacksite": "collisions 0",
            "three_camera_claw_machine": "collisions 0",
            "tomographic_baggage_surgery": "damages 0",
            "portal_freight_oversized_parcel": "collisions 0",
            "zero_g_cable_autopsy": "alarms 0/0",
        }
        for mechanic, marker in clean_acceptance.items():
            self.assertIn(marker, summary["mechanics"][mechanic]["direct_grade"]["feedback"])

    def test_next_ten_difficulty_v3_evidence_supersedes_historical_batch_frames(self) -> None:
        expected = {
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
        }
        environments = {
            environment["mechanic_id"]: environment
            for environment in build_catalog()["environments"]
            if environment["mechanic_id"] in expected
        }
        self.assertEqual(set(environments), expected)
        for mechanic, environment in environments.items():
            self.assertIn("/media/evidence/next_ten_difficulty_v3/", environment["cover"], mechanic)
            self.assertTrue(environment["screenshots"], mechanic)
            self.assertTrue(
                all(
                    "/media/evidence/next_ten_difficulty_v3/" in screenshot["url"]
                    for screenshot in environment["screenshots"]
                ),
                mechanic,
            )
            self.assertTrue(environment["validation"]["ok"], mechanic)

        summary = json.loads(
            (BENCHMARK_ROOT / "evidence/next_ten_difficulty_v3/summary.json").read_text(encoding="utf-8")
        )
        self.assertTrue(summary["ok"])
        self.assertEqual(set(summary["mechanics"]), expected)

    def test_every_built_environment_exposes_real_non_cheat_evidence(self) -> None:
        built = [environment for environment in build_catalog()["environments"] if environment["stage"] == "built"]
        self.assertEqual(len(built), 63)
        for environment in built:
            self.assertTrue(environment["cover"], environment["mechanic_id"])
            self.assertTrue(environment["screenshots"], environment["mechanic_id"])
            for screenshot in environment["screenshots"]:
                self.assertNotIn("cheat", screenshot["url"].lower())
                relative = screenshot["url"].removeprefix("/media/")
                self.assertTrue((BENCHMARK_ROOT / relative).is_file(), screenshot["url"])

    def test_eval_command_is_argument_safe_and_targets_weird_captcha(self) -> None:
        manager = EvaluationManager("avf")
        command, details = manager.build_command({
            "environment_id": "domino_autopsy_env",
            "task_id": "domino_autopsy_seed_0001",
            "agent": "Qwen3VLAgent",
            "model": "Qwen/Qwen3-VL-4B-Thinking",
            "steps": 80,
            "seed": 9,
            "experiment": "dashboard-smoke",
        })
        self.assertIn("weird_captcha_gym", command)
        self.assertIn("domino_autopsy_seed_0001", command)
        self.assertNotIn("shell=True", command)
        self.assertEqual(details["steps"], 80)
        with self.assertRaises(ValueError):
            manager.build_command({
                "environment_id": "domino_autopsy_env",
                "agent": "Qwen3VLAgent; rm -rf /",
                "model": "qwen3-vl",
            })

    def test_static_export_contains_the_full_catalog_without_survey_data(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "site"
            manifest = export_dashboard(output, companion_url="http://127.0.0.1:9123", copy_media=False)
            self.assertFalse(manifest["survey_included"])
            self.assertEqual(manifest["catalog"], {"total": 65, "built": 63, "solution_videos": 11})
            self.assertEqual(manifest["companion_url"], "http://127.0.0.1:9123")
            html = (output / "index.html").read_text(encoding="utf-8")
            app = (output / "static" / "app.js").read_text(encoding="utf-8")
            config = (output / "static" / "config.js").read_text(encoding="utf-8")
            catalog = json.loads((output / "data" / "catalog.json").read_text(encoding="utf-8"))
            self.assertNotIn("Survey Atlas", html)
            self.assertNotIn("/api/atlas", app)
            self.assertIn('\"mode\":\"shared\"', config)
            self.assertEqual(catalog["stats"]["built"], 63)
            self.assertTrue(all(
                not str(environment.get("cover") or "").startswith("/media/")
                for environment in catalog["environments"]
            ))
            with self.assertRaises(ValueError):
                _validate_output_path(Path.home().resolve())
            with self.assertRaises(ValueError):
                _validate_output_path(REPO_ROOT.resolve())

    def test_browser_session_canceled_during_setup_cannot_boot_after_shutdown(self) -> None:
        manager = SessionManager("local")
        setup_started = threading.Event()
        release_setup = threading.Event()
        cancel_observed = threading.Event()
        remove_browser_state = manager._remove_browser_state

        def delayed_setup(*_args: object, **_kwargs: object) -> subprocess.CompletedProcess[str]:
            setup_started.set()
            self.assertTrue(release_setup.wait(timeout=5))
            return subprocess.CompletedProcess([], 0, "", "")

        def observed_remove(job_id: str) -> None:
            remove_browser_state(job_id)
            cancel_observed.set()

        with (
            mock.patch("benchmarks.weird_captcha_gym.dashboard.server.subprocess.run", side_effect=delayed_setup),
            mock.patch("benchmarks.weird_captcha_gym.dashboard.server.subprocess.Popen") as popen,
            mock.patch.object(manager, "_remove_browser_state", side_effect=observed_remove),
        ):
            session = manager.start_browser(
                "domino_autopsy_env",
                "domino_autopsy_seed_0001",
                seed=12,
                auto_open=False,
            )
            self.assertTrue(setup_started.wait(timeout=5))
            manager.cleanup()
            release_setup.set()
            self.assertTrue(cancel_observed.wait(timeout=5))
            self.assertEqual(manager.get(session["id"])["status"], "stopped")
            self.assertFalse(Path(session["state_dir"]).exists())
            popen.assert_not_called()

    def test_companion_requires_pairing_key_and_exact_allowed_origin(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        token = "test-companion-token-with-enough-entropy"
        origin = "https://captcha.example.test"
        server = DashboardServer(
            ("127.0.0.1", 0),
            "avf",
            review_path=Path(temporary.name) / "reviews.json",
            companion_token=token,
            allowed_origins={origin},
        )
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        base = f"http://127.0.0.1:{server.server_address[1]}"
        try:
            health_request = urllib.request.Request(f"{base}/api/health", headers={"Origin": origin})
            with urllib.request.urlopen(health_request, timeout=3) as response:
                health = json.loads(response.read())
                self.assertTrue(health["auth_required"])
                self.assertEqual(response.headers["Access-Control-Allow-Origin"], origin)

            unpaired = urllib.request.Request(f"{base}/api/system", headers={"Origin": origin})
            with self.assertRaises(urllib.error.HTTPError) as unpaired_error:
                urllib.request.urlopen(unpaired, timeout=3)
            self.assertEqual(unpaired_error.exception.code, 401)
            self.assertEqual(unpaired_error.exception.headers["Access-Control-Allow-Origin"], origin)

            paired = urllib.request.Request(
                f"{base}/api/system",
                headers={"Origin": origin, "X-Captcha-Bench-Token": token},
            )
            with urllib.request.urlopen(paired, timeout=3) as response:
                system = json.loads(response.read())
                self.assertTrue(system["companion"])

            hostile = urllib.request.Request(
                f"{base}/api/system",
                headers={"Origin": "https://hostile.example", "X-Captcha-Bench-Token": token},
            )
            with self.assertRaises(urllib.error.HTTPError) as hostile_error:
                urllib.request.urlopen(hostile, timeout=3)
            self.assertEqual(hostile_error.exception.code, 403)

            preflight = urllib.request.Request(
                f"{base}/api/sessions",
                headers={
                    "Origin": origin,
                    "Access-Control-Request-Method": "POST",
                    "Access-Control-Request-Headers": "content-type,x-captcha-bench-token",
                    "Access-Control-Request-Private-Network": "true",
                },
                method="OPTIONS",
            )
            with urllib.request.urlopen(preflight, timeout=3) as response:
                self.assertEqual(response.status, 204)
                self.assertEqual(response.headers["Access-Control-Allow-Private-Network"], "true")
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=3)

    def test_http_server_serves_catalog_frontend_and_rejects_unknown_launch(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        review_path = Path(temporary.name) / "environment-reviews.json"
        server = DashboardServer(
            ("127.0.0.1", 0),
            "avf",
            review_path=review_path,
        )
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        base = f"http://127.0.0.1:{server.server_address[1]}"
        try:
            with urllib.request.urlopen(f"{base}/api/catalog", timeout=3) as response:
                payload = json.loads(response.read())
                self.assertEqual(payload["stats"]["built"], 63)
                photograph = next(
                    environment
                    for environment in payload["environments"]
                    if environment["id"] == "photograph_eats_the_room_env"
                )
                self.assertEqual(photograph["stage"], "built")
                self.assertTrue(photograph["launchable"])
            with urllib.request.urlopen(f"{base}/api/reviews", timeout=3) as response:
                reviews = json.loads(response.read())
                self.assertEqual(reviews["stats"]["total"], 63)
                self.assertEqual(reviews["stats"]["pending"], 63)
            review_request = urllib.request.Request(
                f"{base}/api/reviews/domino_autopsy_env",
                data=json.dumps({"status": "approved", "note": "Hand-tested in TigerVNC."}).encode("utf-8"),
                headers={"content-type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(review_request, timeout=3) as response:
                review = json.loads(response.read())
                self.assertEqual(review["review"]["status"], "approved")
                self.assertEqual(review["stats"]["approved"], 1)
            looks_good_request = urllib.request.Request(
                f"{base}/api/reviews/impossible_panorama_env",
                data=json.dumps({"status": "looks_good", "note": "Solution film reviewed; hands-on pending."}).encode("utf-8"),
                headers={"content-type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(looks_good_request, timeout=3) as response:
                review = json.loads(response.read())
                self.assertEqual(review["review"]["status"], "looks_good")
                self.assertEqual(review["stats"]["looks_good"], 1)
                self.assertEqual(review["stats"]["hands_on_pending"], 62)
            self.assertTrue(review_path.is_file())
            invalid_review = urllib.request.Request(
                f"{base}/api/reviews/domino_autopsy_env",
                data=json.dumps({"status": "revision_requested", "note": ""}).encode("utf-8"),
                headers={"content-type": "application/json"},
                method="POST",
            )
            with self.assertRaises(urllib.error.HTTPError) as raised_review:
                urllib.request.urlopen(invalid_review, timeout=3)
            self.assertEqual(raised_review.exception.code, 400)
            with urllib.request.urlopen(f"{base}/", timeout=3) as response:
                html = response.read().decode("utf-8")
                self.assertIn("Interaction Observatory", html)
            with self.assertRaises(urllib.error.HTTPError) as removed_atlas:
                urllib.request.urlopen(f"{base}/api/atlas", timeout=3)
            self.assertEqual(removed_atlas.exception.code, 404)
            request = urllib.request.Request(
                f"{base}/api/sessions",
                data=json.dumps({"environment_id": "does_not_exist"}).encode("utf-8"),
                headers={"content-type": "application/json"},
                method="POST",
            )
            with self.assertRaises(urllib.error.HTTPError) as raised:
                urllib.request.urlopen(request, timeout=3)
            self.assertEqual(raised.exception.code, 400)

            browser_request = urllib.request.Request(
                f"{base}/api/sessions",
                data=json.dumps({
                    "environment_id": "domino_autopsy_env",
                    "task_id": "domino_autopsy_seed_0001",
                    "seed": 1776,
                    "mode": "browser",
                    "auto_open": False,
                }).encode("utf-8"),
                headers={"content-type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(browser_request, timeout=3) as response:
                browser_session = json.loads(response.read())
            self.assertEqual(browser_session["kind"], "browser")
            deadline = time.monotonic() + 12
            while time.monotonic() < deadline:
                with urllib.request.urlopen(f"{base}/api/sessions", timeout=3) as response:
                    sessions = json.loads(response.read())["sessions"]
                browser_session = next(item for item in sessions if item["id"] == browser_session["id"])
                if browser_session["status"] in {"running", "failed"}:
                    break
                time.sleep(0.1)
            self.assertEqual(browser_session["status"], "running", browser_session.get("logs"))
            self.assertEqual(browser_session["runner"], "local browser")
            browser_url = browser_session["session"]["browser_url"]
            browser_state_dir = Path(browser_session["state_dir"])
            self.assertTrue(browser_state_dir.is_dir())
            with urllib.request.urlopen(browser_url, timeout=3) as response:
                puzzle_html = response.read().decode("utf-8")
            self.assertIn("Weird CAPTCHA Gym", puzzle_html)
            stop_request = urllib.request.Request(
                f"{base}/api/sessions/{browser_session['id']}/stop",
                data=b"{}",
                headers={"content-type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(stop_request, timeout=3) as response:
                self.assertIn(json.loads(response.read())["status"], {"stopping", "stopped"})
            deadline = time.monotonic() + 8
            while time.monotonic() < deadline and browser_state_dir.exists():
                time.sleep(0.05)
            self.assertFalse(browser_state_dir.exists())
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=3)


if __name__ == "__main__":
    unittest.main()
