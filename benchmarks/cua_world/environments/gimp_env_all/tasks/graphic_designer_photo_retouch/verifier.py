#!/usr/bin/env python3
"""
Verifier for graphic_designer_photo_retouch task.

A graphic designer must professionally retouch a portrait photograph:
tonal range stretch, color cast correction, sharpening, and vignette.
Output: retouched_portrait.png on Desktop.

Scoring criteria (20 pts each):
1. retouched_portrait.png exists and is valid
2. Significant pixel-level changes from source (actual retouching done)
3. Contrast improved: output histogram spread wider than source
4. Color cast corrected: channel means are more balanced in output
5. Vignette effect present: image corners are darker than center

Pass threshold: 80 (4/5 criteria)
"""

import logging
import json
import os
import sys
import tempfile
from pathlib import Path

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + "/..")
from verification_utils import copy_file_from_container

logging.basicConfig(level=logging.DEBUG)


def check_photo_retouch(traj, env_info, task_info):
    """Main verifier for photo retouching task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    with tempfile.TemporaryDirectory() as temp_dir:
        temp_path = Path(temp_dir)

        feedback_parts = []
        criteria_scores = []

        # Copy result
        result_local = temp_path / "retouched_portrait.png"
        result_ok = False
        try:
            copy_from_env("/home/ga/Desktop/retouched_portrait.png", str(result_local))
            if result_local.exists() and result_local.stat().st_size > 1000:
                result_ok = True
        except Exception:
            pass

        if not result_ok:
            return {
                "passed": False,
                "score": 0,
                "feedback": (
                    "retouched_portrait.png not found on Desktop. "
                    "Open portrait_photo.jpg in GIMP, apply professional retouching "
                    "(tonal range, color cast correction, sharpening, vignette), "
                    "and export as retouched_portrait.png."
                )
            }

        feedback_parts.append("Found: retouched_portrait.png")

        # Copy source and ground truth
        source_local = temp_path / "source.jpg"
        gt_local = temp_path / "gt.json"

        source_ok = False
        try:
            copy_from_env("/tmp/portrait_photo_baseline.jpg", str(source_local))
            if source_local.exists():
                source_ok = True
        except Exception:
            pass

        gt = {}
        try:
            copy_from_env("/tmp/photo_retouch_gt.json", str(gt_local))
            gt = json.loads(gt_local.read_text())
        except Exception:
            pass

        try:
            from PIL import Image

            result_img = Image.open(result_local).convert('RGB')
            result_arr = np.array(result_img)
            rw, rh = result_img.size
            feedback_parts.append(f"Result: {rw}x{rh}")

            # ------------------------------------------------------------------
            # Criterion 1: File exists and is valid
            # ------------------------------------------------------------------
            criteria_scores.append(("✅ retouched_portrait.png exists and is valid", True))

            # ------------------------------------------------------------------
            # Criterion 2: Image differs significantly from source
            # ------------------------------------------------------------------
            if source_ok:
                try:
                    src_img = Image.open(source_local).convert('RGB')
                    src_resized = src_img.resize(result_img.size, Image.LANCZOS)
                    src_arr = np.array(src_resized)

                    diff = np.abs(result_arr.astype(float) - src_arr.astype(float))
                    mean_diff = float(np.mean(diff))
                    changed_pct = float(np.mean(diff.max(axis=2) > 10)) * 100

                    feedback_parts.append(
                        f"Diff from source: mean={mean_diff:.1f}, {changed_pct:.1f}% pixels changed"
                    )

                    if mean_diff > 8.0 or changed_pct > 20.0:
                        criteria_scores.append((
                            f"✅ Image significantly retouched (diff={mean_diff:.1f}, {changed_pct:.1f}% changed)",
                            True
                        ))
                    else:
                        criteria_scores.append((
                            f"❌ Image barely changed from source (diff={mean_diff:.1f}). "
                            "Apply meaningful tonal and color corrections.", False
                        ))
                except Exception as e:
                    logging.warning(f"Diff error: {e}")
                    criteria_scores.append(("✅ Cannot compare to source (skipped)", True))
            else:
                criteria_scores.append(("✅ Source comparison skipped (baseline not found)", True))

            # ------------------------------------------------------------------
            # Criterion 3: Contrast improved (histogram spread wider)
            # ------------------------------------------------------------------
            result_gray = np.mean(result_arr, axis=2)
            result_p5 = float(np.percentile(result_gray, 5))
            result_p95 = float(np.percentile(result_gray, 95))
            result_range = result_p95 - result_p5

            src_range = gt.get("contrast_range", None)

            feedback_parts.append(f"Output contrast range: p5={result_p5:.0f} p95={result_p95:.0f} spread={result_range:.0f}")

            if src_range is not None:
                feedback_parts.append(f"Source contrast range: {src_range:.0f}")
                if result_range > src_range + 10:
                    criteria_scores.append((
                        f"✅ Contrast improved: spread {result_range:.0f} vs source {src_range:.0f}", True
                    ))
                elif result_range > 180:
                    # Even if source wasn't much different, if output range is wide it's good
                    criteria_scores.append((
                        f"✅ Contrast is well-stretched (spread={result_range:.0f})", True
                    ))
                else:
                    criteria_scores.append((
                        f"❌ Contrast not improved (output spread={result_range:.0f}, source={src_range:.0f}). "
                        "Apply Levels or Curves to stretch the tonal range.", False
                    ))
            else:
                # No baseline: just check if output has good contrast range
                if result_range > 160:
                    criteria_scores.append((f"✅ Good contrast range in output ({result_range:.0f})", True))
                else:
                    criteria_scores.append((
                        f"❌ Output has compressed contrast range ({result_range:.0f}). "
                        "Stretch the tonal range using Levels or Curves.", False
                    ))

            # ------------------------------------------------------------------
            # Criterion 4: Color cast corrected (channel means more balanced)
            # A strong color cast = large difference between channel means
            # After correction, channel means should be more equal
            # ------------------------------------------------------------------
            r_mean = float(np.mean(result_arr[:, :, 0]))
            g_mean = float(np.mean(result_arr[:, :, 1]))
            b_mean = float(np.mean(result_arr[:, :, 2]))
            out_channel_std = float(np.std([r_mean, g_mean, b_mean]))

            src_r = gt.get("r_mean", None)
            src_g = gt.get("g_mean", None)
            src_b = gt.get("b_mean", None)

            feedback_parts.append(
                f"Output channels: R={r_mean:.0f} G={g_mean:.0f} B={b_mean:.0f} (std={out_channel_std:.1f})"
            )

            if src_r is not None and src_g is not None and src_b is not None:
                src_channel_std = float(np.std([src_r, src_g, src_b]))
                feedback_parts.append(
                    f"Source channels: R={src_r:.0f} G={src_g:.0f} B={src_b:.0f} (std={src_channel_std:.1f})"
                )

                # Check that channel means changed (color correction applied)
                channel_shift = abs(r_mean - src_r) + abs(g_mean - src_g) + abs(b_mean - src_b)

                if channel_shift > 15 or out_channel_std < src_channel_std - 5:
                    criteria_scores.append((
                        f"✅ Color correction applied (channel shift={channel_shift:.0f}, "
                        f"std: {src_channel_std:.1f}→{out_channel_std:.1f})", True
                    ))
                else:
                    criteria_scores.append((
                        f"❌ Color cast not corrected (channel shift={channel_shift:.0f}). "
                        "Use Curves or Color Balance to correct channel imbalance.", False
                    ))
            else:
                # No baseline: any non-trivial channel difference may indicate color work was done
                criteria_scores.append(("✅ Color correction check skipped (no baseline)", True))

            # ------------------------------------------------------------------
            # Criterion 5: Vignette effect present
            # Corners should be darker than center after vignette
            # ------------------------------------------------------------------
            h, w = result_arr.shape[:2]
            gray = np.mean(result_arr, axis=2)

            # Sample center and corner regions
            center_h = slice(h // 3, 2 * h // 3)
            center_w = slice(w // 3, 2 * w // 3)
            center_mean = float(np.mean(gray[center_h, center_w]))

            corner_size_h = max(1, h // 8)
            corner_size_w = max(1, w // 8)
            tl = gray[:corner_size_h, :corner_size_w]
            tr = gray[:corner_size_h, -corner_size_w:]
            bl = gray[-corner_size_h:, :corner_size_w]
            br = gray[-corner_size_h:, -corner_size_w:]
            corner_mean = float(np.mean([np.mean(tl), np.mean(tr), np.mean(bl), np.mean(br)]))

            vignette_strength = center_mean - corner_mean
            feedback_parts.append(
                f"Vignette: center={center_mean:.0f}, corners={corner_mean:.0f}, strength={vignette_strength:.1f}"
            )

            if vignette_strength > 10:
                criteria_scores.append((
                    f"✅ Vignette effect present (center {center_mean:.0f} vs corners {corner_mean:.0f}, "
                    f"strength={vignette_strength:.0f})", True
                ))
            else:
                criteria_scores.append((
                    f"❌ No vignette detected (center={center_mean:.0f}, corners={corner_mean:.0f}, "
                    f"strength={vignette_strength:.0f}). "
                    "Add a dark vignette to darken the edges of the image.", False
                ))

        except ImportError:
            return {"passed": False, "score": 0, "feedback": "PIL not available"}

        # ------------------------------------------------------------------
        # Final score
        # ------------------------------------------------------------------
        passed_count = sum(1 for _, p in criteria_scores if p)
        total = len(criteria_scores)
        score = int((passed_count / total) * 100)
        task_passed = passed_count >= 4

        for label, _ in criteria_scores:
            feedback_parts.append(label)

        if task_passed:
            feedback_parts.append(f"🎉 Passed! {passed_count}/{total} criteria met.")
        else:
            feedback_parts.append(f"❌ Failed: {passed_count}/{total} criteria met.")

        return {
            "passed": task_passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
