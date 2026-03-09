from __future__ import annotations

import logging
from pathlib import Path
from typing import Any

import numpy as np
from PIL import Image


logger = logging.getLogger(__name__)


def _score(value: bool) -> float:
    return 1.0 if value else 0.0


def _open_rgb(path: str) -> Image.Image:
    return Image.open(path).convert("RGB")


def _resize_pair(img_a: Image.Image, img_b: Image.Image) -> tuple[Image.Image, Image.Image]:
    if img_a.size == img_b.size:
        return img_a, img_b
    return img_a, img_b.resize(img_a.size)


def _structure_similarity_images(img_a: Image.Image, img_b: Image.Image, threshold: float = 0.9) -> float:
    img_a, img_b = _resize_pair(img_a.convert("RGB"), img_b.convert("RGB"))
    arr_a = np.asarray(img_a, dtype=np.float32)
    arr_b = np.asarray(img_b, dtype=np.float32)
    diff = np.abs(arr_a - arr_b).mean()
    return _score(diff <= (255.0 * (1.0 - threshold)))


def _structure_similarity(path_a: str, path_b: str, threshold: float = 0.9) -> float:
    return _structure_similarity_images(_open_rgb(path_a), _open_rgb(path_b), threshold=threshold)


def check_config_status(config_path: str, rule: dict[str, Any]) -> float:
    text = Path(config_path).read_text(encoding="utf-8", errors="ignore")
    key = str(rule.get("key", "")).strip()
    value = str(rule.get("value", "")).strip()
    return _score(key in text and value in text)


def check_triangle_position(result_path: str) -> float:
    img = _open_rgb(result_path)
    arr = np.asarray(img, dtype=np.uint8)
    brightness = arr.mean(axis=2)
    mask = brightness < 220
    coords = np.argwhere(mask)
    if coords.size == 0:
        return 0.0
    center_y, center_x = coords.mean(axis=0)
    target_x = img.width / 2
    target_y = img.height / 2
    tolerance_x = img.width * 0.15
    tolerance_y = img.height * 0.15
    return _score(abs(center_x - target_x) <= tolerance_x and abs(center_y - target_y) <= tolerance_y)


def check_saturation_increase_and_structure_sim(src_path: str, tgt_path: str) -> float:
    src = _open_rgb(src_path).convert("HSV")
    tgt = _open_rgb(tgt_path).convert("HSV").resize(src.size)
    src_sat = np.asarray(src)[:, :, 1].mean()
    tgt_sat = np.asarray(tgt)[:, :, 1].mean()
    return _score(tgt_sat > src_sat and _structure_similarity(src_path, tgt_path) >= 1.0)


def check_image_size(path: str, rule: dict[str, Any]) -> float:
    img = Image.open(path)
    width = rule.get("width")
    height = rule.get("height")
    ok = True
    if width is not None:
        ok = ok and img.width == int(width)
    if height is not None:
        ok = ok and img.height == int(height)
    return _score(ok)


def check_structure_sim_resized(src_path: str, tgt_path: str) -> float:
    src = _open_rgb(src_path)
    tgt = _open_rgb(tgt_path).resize(src.size)
    return _structure_similarity_images(src, tgt)


def check_structure_sim(src_path: str, tgt_path: str) -> float:
    return _structure_similarity(src_path, tgt_path)


def check_palette_and_structure_sim(src_path: str, tgt_path: str) -> float:
    tgt = Image.open(tgt_path)
    palette_ok = tgt.mode in {"P", "PA"}
    return _score(palette_ok and _structure_similarity(src_path, tgt_path) >= 1.0)


def check_green_background(src_path: str, tgt_path: str) -> float:
    img = _open_rgb(tgt_path)
    arr = np.asarray(img)
    border = np.concatenate(
        [
            arr[:20, :, :].reshape(-1, 3),
            arr[-20:, :, :].reshape(-1, 3),
            arr[:, :20, :].reshape(-1, 3),
            arr[:, -20:, :].reshape(-1, 3),
        ],
        axis=0,
    )
    mean = border.mean(axis=0)
    is_green = mean[1] > mean[0] + 40 and mean[1] > mean[2] + 40
    return _score(is_green and _structure_similarity(src_path, tgt_path, threshold=0.7) >= 1.0)


def check_file_exists_and_structure_sim(actual_path: str, expected_path: str) -> float:
    return _score(Path(actual_path).exists() and _structure_similarity(expected_path, actual_path) >= 1.0)


def check_contrast_increase_and_structure_sim(src_path: str, tgt_path: str) -> float:
    src = np.asarray(_open_rgb(src_path), dtype=np.float32)
    tgt = np.asarray(_open_rgb(tgt_path).resize((_open_rgb(src_path).size)), dtype=np.float32)
    src_std = src.std()
    tgt_std = tgt.std()
    return _score(tgt_std > src_std and _structure_similarity(src_path, tgt_path, threshold=0.75) >= 1.0)


def check_brightness_decrease_and_structure_sim(src_path: str, tgt_path: str) -> float:
    src_img = _open_rgb(src_path)
    tgt_img = _open_rgb(tgt_path).resize(src_img.size)
    src = np.asarray(src_img, dtype=np.float32)
    tgt = np.asarray(tgt_img, dtype=np.float32)
    return _score(tgt.mean() < src.mean() and _structure_similarity_images(src_img, tgt_img, threshold=0.75) >= 1.0)


def check_image_mirror(src_path: str, tgt_path: str) -> float:
    src = _open_rgb(src_path).transpose(Image.FLIP_LEFT_RIGHT)
    tgt = _open_rgb(tgt_path).resize(src.size)
    src_arr = np.asarray(src, dtype=np.float32)
    tgt_arr = np.asarray(tgt, dtype=np.float32)
    diff = np.abs(src_arr - tgt_arr).mean()
    return _score(diff <= 10.0)


__all__ = [
    "check_brightness_decrease_and_structure_sim",
    "check_config_status",
    "check_contrast_increase_and_structure_sim",
    "check_file_exists_and_structure_sim",
    "check_green_background",
    "check_image_mirror",
    "check_image_size",
    "check_palette_and_structure_sim",
    "check_saturation_increase_and_structure_sim",
    "check_structure_sim",
    "check_structure_sim_resized",
    "check_triangle_position",
]
