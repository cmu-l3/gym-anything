"""Match each env folder to a row in gym_anything_selected_products.csv.

Strategy:
  1. Collect candidate names from the env folder name + env.json `id`,
     `description`, `tags`, and `category`.
  2. Score each (env_name, product_name) pair with a normalized-substring +
     SequenceMatcher hybrid; the env folder name is the strongest signal.
  3. Apply explicit MANUAL_OVERRIDES for envs whose product name diverges
     too much for fuzzy matching to be reliable.
  4. Write data/env_to_product.json so downstream stages don't recompute.

This is run once and the artifact is committed; downstream stages just read.
"""

from __future__ import annotations

import csv
import difflib
import json
import logging
import re
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple

from .ingest import iter_envs
from .paths import ENV_DIR, ENV_PRODUCT_MAP, gdp_dir

logger = logging.getLogger(__name__)

# Envs that are framework presets / demos / placeholders, not real software.
# Excluded from the visualizer entirely.
NON_PRODUCT_ENVS: set = {
    "preset_gnome_systemd",
    "preset_x11",
    "simple_user_setup",
    "user_permissions_demo",
    "apptainer_gnome_env",
}


# Hand-curated where fuzzy matching is unreliable. Left = env folder name.
# Right = product name in either gym_anything_selected_products.csv or
# gdp_weighting/product_totals.csv (selected is preferred when both match).
MANUAL_OVERRIDES: Dict[str, str] = {
    # Browsers — chrome envs are substitutes (gym-anything substitutes paid Chrome)
    "chrome_env_all": "Mozilla Firefox",
    "chrome_env_osw": "Mozilla Firefox",
    "firefox_env": "Mozilla Firefox",
    # Office substitutes
    "apache_openoffice_env": "Apache OpenOffice",
    "draw_desktop_env": "Apache OpenOffice",
    "libreoffice_writer_env": "LibreOffice",
    "calligra_words_env": "Calligra Words",
    # Common alias/abbreviation forms
    "blender3d_env": "Blender",
    "blenderbim_env": "BlenderBIM",
    "free_scout_env": "FreeScout",
    "tcl_tk_env": "Tcl/Tk",
    "ninja_trader_env": "NinjaTrader",
    "active_inspire_env": "ActivInspire",
    "active_inspire_windows_env": "ActivInspire",
    "diagrams_net_env": "Diagrams.net Desktop",
    "tiddly_wiki_env": "TiddlyWiki",
    "claude_thunderbird": "Mozilla Thunderbird",
    "bluemail_env": "BlueMail",
    "btcpay_server_env": "BTCPay Server",
    "twon_access_commander_env": "2N Access Commander",
    "blue_sky_plan_env": "Blue Sky Plan",
    "copper_point_of_sale_env": "Copper Point of Sale",
    "code_saturne_env": "Code Saturne",
    "android_aps_env": "AndroidAPS",
    "android_studio_env": "Android Studio",
    "android_calculator_env": "Android Calculator",
    "android_avd_calculator_env": "Android Calculator",
    "azure_devops_server_env": "Azure DevOps Server",
    "google_earth_pro_env": "Google Earth Pro",
    "google_earth_pro_windows_env": "Google Earth Pro",
    "docker_desktop_env": "Docker Desktop",
    "docker_env": "Docker Desktop",
    "kicad_env_all": "KiCad",
    "qgroundcontrol_env": "QGroundControl",
    "fr_eedom_env": "Freedom",
    "anaconda_env": "Anaconda",
    "tier_ii_submit_env": "Tier II Submit",
    "icse_dataworks_env": "ICSE-DataWorks",
    "twincat_env": "TwinCAT",
    "scilab_env": "Scilab",
    "yt_dlp_env": "yt-dlp",
    "easy_ocr_env": "EasyOCR",
    "openemr_env": "OpenEMR",
    "openmrs_env": "OpenMRS",
    "openrocket_env": "OpenRocket",
    "open_lca_env": "openLCA",
    "openlca_env": "openLCA",
    "openshot_env": "OpenShot",
    "open_shot_env": "OpenShot",
    "open_toonz_env": "OpenToonz",
    "opentoonz_env": "OpenToonz",
    "openvsp_env": "OpenVSP",
    "openboard_env": "OpenBoard",
    "openbci_gui_env": "OpenBCI GUI",
    "open_office_env": "Apache OpenOffice",
    "snap_env": "SNAP",
    "freecad_env": "FreeCAD",
    "freecadbim_env": "FreeCAD BIM",
    "kstars_env": "KStars",
    "kstars_sim_env": "KStars",
    "stellarium_env": "Stellarium",
    "pymol_env": "PyMOL",
    "rstudio_env": "RStudio",
    "jasp_env": "JASP",
    "moodle_env": "Moodle",
    "canvas_lms_env": "Canvas LMS",
    "thunderbird_env": "Mozilla Thunderbird",
    "mozilla_thunderbird_env": "Mozilla Thunderbird",
    "wireshark_env": "Wireshark",
    "wazuh_env": "Wazuh",
    "splunk_env": "Splunk Enterprise",
    "autopsy_env": "Autopsy",
    "audacity_env": "Audacity",
    "ardour_env": "Ardour",
    "blender_env": "Blender",
    "qgis_env": "QGIS",
    "sumo_env": "SUMO",
    "veracrypt_env": "VeraCrypt",
    "panoply_env": "Panoply",
    "qblade_env": "QBlade",
    "webots_env": "Webots",
    "coppeliasim_env": "CoppeliaSim",
    "ardour_env_all": "Ardour",
    "gimp_env_all": "GIMP",
    "gimp_env": "GIMP",
    "vlc_env": "VLC media player",
    "wpe_env": "WPE",
    "ms_word_env": "Microsoft Word",
    "ms_excel_env": "Microsoft Excel",
    "ms_powerpoint_env": "Microsoft PowerPoint",
    "office_excel_env": "Microsoft Excel",
    "office_word_env": "Microsoft Word",
    "office_powerpoint_env": "Microsoft PowerPoint",
    # Previously unmatched
    "bridgecommand_env": "Bridge Command",
    "google_earth_env_final": "Google Earth Pro",
    "google_earth_env": "Google Earth Pro",
    "google_earth_env_bak": "Google Earth Pro",
    "gpredict_env": "Gpredict",
    "seiscomp_env": "SeisComP",
    "slicer3d_env": "3D Slicer",
    "subway_surfers_env": "Subway Surfers",
    "vlc_media_player_env": "VLC media player",
    "vlc_env": "VLC media player",
    # Wrong fuzzy results (DB substring confusion)
    "emoncms_env": "Emoncms",
    "magento_env": "Magento",
    "manageservice_env": "Manage Service",
    "frog_seo_spider_env": "Screaming Frog SEO Spider",
    "freecad_envb": "FreeCAD",
    "gimp_env_all_fast": "GIMP",
    "docker_desktop_env_temp_codex": "Docker Desktop",
    "docker_desktop_env_temp_gemini": "Docker Desktop",
    # Final round
    "vital_recorder_windows_env": "Vital Recorder",
    "vscode_env": "Visual Studio Code",
    "visual_studio_2022_env": "Visual Studio",
    "microsoft_excel_2010_env": "Microsoft Excel",
    "microsoft_word_starter_env": "Microsoft Word",
    "ms_sql_server_env": "Microsoft SQL Server",
    "onlyoffice_env": "OnlyOffice",
    "openc3_cosmos_env": "OpenC3 COSMOS",
    "sygic_gps_env": "Sygic GPS Navigation",
}


_STOPWORDS = {"env", "all", "osw", "windows", "linux", "android", "app", "gui", "free", "the", "for", "of", "and"}


def _norm(s: str) -> str:
    s = s.lower().strip()
    s = re.sub(r"[\s_\-./]+", " ", s)
    s = re.sub(r"\s+", " ", s).strip()
    tokens = [t for t in s.split() if t and t not in _STOPWORDS]
    return " ".join(tokens)


def _tokens(s: str) -> set:
    return {t for t in _norm(s).split() if len(t) >= 2}


def _candidate_names(env_root: Path) -> List[str]:
    """Pull names from env folder + env.json fields."""
    out: List[str] = []
    out.append(env_root.name)
    env_json_path = env_root / "env.json"
    if env_json_path.is_file():
        try:
            spec = json.loads(env_json_path.read_text(encoding="utf-8"))
        except Exception:
            spec = {}
        if "id" in spec:
            out.append(str(spec["id"]).split("@")[0])
        desc = str(spec.get("description") or "")
        first = desc.split(".")[0].split("\n")[0].strip()
        if first:
            out.append(first)
        for tag in spec.get("tags") or []:
            out.append(str(tag))
    return out


def _score_norm(q_norm: str, t_norm: str) -> float:
    if not q_norm or not t_norm:
        return 0.0
    if q_norm == t_norm:
        return 1.0
    sub = 0.0
    if q_norm in t_norm or t_norm in q_norm:
        sub = 0.6 + 0.4 * min(len(q_norm), len(t_norm)) / max(len(q_norm), len(t_norm))
    seq = difflib.SequenceMatcher(None, q_norm, t_norm).ratio()
    return max(seq, sub)


def _best_product(
    env_root: Path,
    products_norm: List[Tuple[str, str, set]],
    threshold: float = 0.78,
) -> Tuple[Optional[str], float]:
    """Find best product. `products_norm` is a list of (orig, normalized, token_set)."""
    raw_candidates = _candidate_names(env_root)
    if not raw_candidates:
        return None, 0.0

    # Precompute normalized + token sets for the candidates.
    candidates: List[Tuple[str, set, float]] = []
    for idx, raw in enumerate(raw_candidates):
        n = _norm(raw)
        if not n:
            continue
        weight = 1.0 if idx == 0 else 0.85
        candidates.append((n, _tokens(raw), weight))
    if not candidates:
        return None, 0.0

    # Token union for fast filtering: a product must share at least one token
    # with one of the candidates to be worth a SequenceMatcher.ratio() call.
    candidate_tokens = set()
    for _, toks, _ in candidates:
        candidate_tokens |= toks

    best_name: Optional[str] = None
    best_score: float = 0.0

    for orig, p_norm, p_toks in products_norm:
        if not (p_toks & candidate_tokens):
            continue
        for c_norm, _, weight in candidates:
            s = _score_norm(c_norm, p_norm) * weight
            if s > best_score:
                best_score = s
                best_name = orig

    if best_score < threshold:
        return None, best_score
    return best_name, best_score


def _read_csv(path: Path) -> List[Dict[str, Any]]:
    if not path.is_file():
        raise RuntimeError(f"missing CSV: {path}")
    with path.open("r", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def _load_product_universe(gdp_root: Path) -> Tuple[List[str], set, set]:
    """Return (all_names, in_selected, in_totals).

    A product name appears in `all_names` if it shows up in EITHER the selected
    set or the broader product_totals (the latter is the union of GDP-attributed
    products). Selected names are preferred when both have a match, since they
    carry richer per-tier metadata.
    """
    selected = _read_csv(gdp_root / "gym_anything_selected_products.csv")
    totals = _read_csv(gdp_root / "gdp_weighting" / "product_totals.csv")
    selected_names = {r["product"] for r in selected}
    totals_names = {r["product"] for r in totals}
    union = list(selected_names | totals_names)
    return union, selected_names, totals_names


def run(env_dir: Optional[Path] = None, output: Optional[Path] = None) -> Dict[str, Any]:
    """Build env_id → product mapping. Returns the dict and writes JSON."""
    if env_dir is None:
        env_dir = ENV_DIR
    if output is None:
        output = ENV_PRODUCT_MAP
    product_names, selected_names, totals_names = _load_product_universe(gdp_dir())

    # Precompute normalized + token sets for all products once.
    products_norm: List[Tuple[str, str, set]] = []
    for p in product_names:
        n = _norm(p)
        if not n:
            continue
        products_norm.append((p, n, _tokens(p)))

    mapping: Dict[str, Dict[str, Any]] = {}
    unmatched: List[str] = []
    fuzzy: List[Tuple[str, str, float]] = []
    excluded: List[str] = []

    for env_root in iter_envs(env_dir):
        env_id = env_root.name
        if env_id in NON_PRODUCT_ENVS:
            excluded.append(env_id)
            continue
        if env_id in MANUAL_OVERRIDES:
            chosen = MANUAL_OVERRIDES[env_id]
            confidence = 1.0
            method = "manual"
            if chosen not in selected_names and chosen not in totals_names:
                logger.warning(
                    "Manual override for %s points to %r which is in NEITHER CSV",
                    env_id, chosen,
                )
        else:
            chosen, confidence = _best_product(env_root, products_norm)
            method = "fuzzy"
        if chosen is None:
            unmatched.append(env_id)
            mapping[env_id] = {
                "product": None,
                "confidence": round(confidence, 3),
                "method": "unmatched",
                "in_selected": False,
            }
            continue
        if method == "fuzzy" and confidence < 0.92:
            fuzzy.append((env_id, chosen, round(confidence, 3)))
        mapping[env_id] = {
            "product": chosen,
            "confidence": round(confidence, 3),
            "method": method,
            "in_selected": chosen in selected_names,
        }

    output.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "products_csv_selected": str(gdp_dir() / "gym_anything_selected_products.csv"),
        "products_csv_totals": str(gdp_dir() / "gdp_weighting" / "product_totals.csv"),
        "n_envs": len(mapping),
        "n_unmatched": len(unmatched),
        "n_excluded_non_product": len(excluded),
        "excluded": excluded,
        "unmatched": unmatched,
        "fuzzy_low_confidence": [
            {"env_id": e, "product": p, "confidence": c} for e, p, c in fuzzy
        ],
        "map": mapping,
    }
    output.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    logger.info(
        "env→product map: %d envs, %d unmatched, %d low-confidence fuzzy, %d excluded → %s",
        len(mapping), len(unmatched), len(fuzzy), len(excluded), output,
    )
    return payload


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    result = run()
    print(f"unmatched: {result['n_unmatched']}")
    if result["unmatched"]:
        print("first 20 unmatched:", result["unmatched"][:20])
