"""Verifier for finder_env's build_recipe_smart_folder task.

Scoring (100 points, pass at 70):
- 15 pts  C1 (subfolders)       3 pts × 5 cuisine subfolders exist.
- 30 pts  C2 (files_correct)    proportional: each file in correct cuisine folder.
- 25 pts  C3 (name_format)      proportional: lowercase_underscore.txt filenames.
- 20 pts  C4 (yellow_tags)      proportional: Yellow tag on every file.
- 10 pts  C5 (smart_folder)     .savedSearch plist exists with Yellow + Recipes scope.
"""
from __future__ import annotations

import json
import logging
import os
import plistlib
import re
import tempfile
from typing import Any, Dict

logger = logging.getLogger(__name__)

EXPECTED: dict[str, tuple[str, str]] = {
    "Pasta Carbonara from Nonna.txt": ("Italian", "pasta_carbonara_from_nonna.txt"),
    "Homemade Margherita Pizza.txt": ("Italian", "homemade_margherita_pizza.txt"),
    "Risotto ai Funghi.txt": ("Italian", "risotto_ai_funghi.txt"),
    "Tiramisu Classic.txt": ("Italian", "tiramisu_classic.txt"),
    "Osso Buco Milanese.txt": ("Italian", "osso_buco_milanese.txt"),
    "Pad Thai Noodles.txt": ("Asian", "pad_thai_noodles.txt"),
    "Japanese Miso Soup.txt": ("Asian", "japanese_miso_soup.txt"),
    "Korean Bibimbap Bowl.txt": ("Asian", "korean_bibimbap_bowl.txt"),
    "Chicken Fried Rice Easy.txt": ("Asian", "chicken_fried_rice_easy.txt"),
    "Vietnamese Pho Broth.txt": ("Asian", "vietnamese_pho_broth.txt"),
    "Street Tacos al Pastor.txt": ("Mexican", "street_tacos_al_pastor.txt"),
    "Homemade Guacamole.txt": ("Mexican", "homemade_guacamole.txt"),
    "Black Bean Enchiladas.txt": ("Mexican", "black_bean_enchiladas.txt"),
    "Churros with Chocolate.txt": ("Mexican", "churros_with_chocolate.txt"),
    "Sourdough Bread Beginner.txt": ("Baking", "sourdough_bread_beginner.txt"),
    "Chocolate Chip Cookies Classic.txt": ("Baking", "chocolate_chip_cookies_classic.txt"),
    "Banana Bread Moist.txt": ("Baking", "banana_bread_moist.txt"),
    "Greek Salad Simple.txt": ("Other", "greek_salad_simple.txt"),
    "Moroccan Lamb Tagine.txt": ("Other", "moroccan_lamb_tagine.txt"),
    "French Onion Soup.txt": ("Other", "french_onion_soup.txt"),
}

SUBFOLDERS = ["Italian", "Asian", "Mexican", "Baking", "Other"]
REMOTE_RESULT = "/tmp/build_recipe_smart_folder_result.json"


def _is_valid_name(name: str) -> bool:
    stem = name[:-4] if name.endswith(".txt") else name
    return bool(re.fullmatch(r"[a-z][a-z0-9_]*", stem))


def verify_build_recipe_smart_folder(
    traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]
) -> Dict[str, Any]:
    del traj, task_info

    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"score": 0, "passed": False, "feedback": "env_info missing copy_from_env"}

    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as f:
        local_path = f.name
    try:
        try:
            copy_from_env(REMOTE_RESULT, local_path)
        except Exception as exc:
            return {"score": 0, "passed": False,
                    "feedback": f"Could not retrieve result file: {exc}"}
        with open(local_path, encoding="utf-8") as fh:
            data: dict = json.load(fh)
    finally:
        try:
            os.unlink(local_path)
        except Exception:
            pass

    score = 0
    details: list[str] = []

    # C1: Five cuisine subfolders exist (15 pts — 3 each)
    c1 = 0
    for sf in SUBFOLDERS:
        if data.get("folders_exist", {}).get(sf):
            c1 += 3
        else:
            details.append(f"Missing subfolder: {sf}")
    score += c1

    # C2: Files in correct cuisine folder (30 pts proportional)
    files_by_folder: dict[str, set] = {
        sf: set(data.get("files_by_folder", {}).get(sf, []))
        for sf in SUBFOLDERS
    }
    c2_correct = 0
    for _orig, (expected_folder, expected_name) in EXPECTED.items():
        if expected_name in files_by_folder.get(expected_folder, set()):
            c2_correct += 1
        else:
            details.append(f"'{expected_name}' not in {expected_folder}/")
    c2 = round(c2_correct * 30 / 20)
    score += c2

    # C3: lowercase_underscore filenames (25 pts proportional)
    all_present: list[str] = [f for sf in SUBFOLDERS for f in files_by_folder[sf]]
    if not all_present:
        c3 = 0
        details.append("No files found in any recipe subfolder")
    else:
        bad_names = [n for n in all_present if not _is_valid_name(n)]
        if not bad_names:
            c3 = 25
        else:
            c3 = round(25 * (len(all_present) - len(bad_names)) / len(all_present))
        if bad_names:
            details.append(f"Files with bad names: {bad_names[:3]}")
    score += c3

    # C4: Yellow tag on each file (20 pts proportional)
    tags: dict = data.get("tags_by_file", {})
    tagged = sum(1 for tags_list in tags.values() if "Yellow" in tags_list)
    total_files = len(tags)
    c4 = round(tagged * 20 / max(total_files, 20)) if total_files else 0
    if tagged < total_files:
        details.append(f"Only {tagged}/{total_files} files have Yellow tag")
    score += c4

    # C5: Smart Folder with Yellow tag + Recipes scope (10 pts)
    c5 = 0
    if data.get("smart_folder_exists"):
        c5 += 4
        raw_hex = data.get("smart_folder_content", "")
        if raw_hex:
            try:
                pl = plistlib.loads(bytes.fromhex(raw_hex))
                raw_query = pl.get("RawQuery", "") or ""
                scopes = pl.get("SearchScopes", [])
                if "Yellow" in str(raw_query):
                    c5 += 3
                else:
                    details.append("Smart Folder query does not reference Yellow tag")
                if any("Recipes" in str(s) for s in scopes):
                    c5 += 3
                else:
                    details.append("Smart Folder scope does not include Recipes folder")
            except Exception as e:
                details.append(f"Smart Folder plist parse error: {e}")
    else:
        details.append("Smart Folder ~/Library/Saved Searches/My Recipes.savedSearch not found")
    score += c5

    passed = score >= 70
    feedback = f"Score: {score}/100. " + ("; ".join(details) if details else "All criteria met.")
    return {"passed": passed, "score": score, "feedback": feedback}
