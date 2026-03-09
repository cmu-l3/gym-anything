#!/usr/bin/env python3
"""
Verifier for personality_efa task (jamovi_env).

Parses the saved .omv file (a ZIP archive) and inspects index.html to verify
that the agent correctly configured an Exploratory Factor Analysis on the
25-item Big Five personality inventory.

Scoring rubric (100 points total, pass threshold 70):
  Criterion 1 (15 pts): File saved at the correct path
  Criterion 2 (10 pts): Valid .omv structure (ZIP with expected contents)
  Criterion 3 (20 pts): EFA analysis present in the output
  Criterion 4 (15 pts): Correct number of factors (5)
  Criterion 5 (15 pts): Oblimin rotation used
  Criterion 6 (15 pts): KMO and Bartlett's test present
  Criterion 7 (10 pts): Factor loadings show personality items (not gender/age)
"""

import json
import logging
import os
import re
import tempfile
import zipfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

OMV_OUTPUT_FILE = "/home/ga/Documents/Jamovi/BFI_FactorAnalysis.omv"
PASS_THRESHOLD = 70

PERSONALITY_ITEMS = [
    "A1", "A2", "A3", "A4", "A5",
    "C1", "C2", "C3", "C4", "C5",
    "E1", "E2", "E3", "E4", "E5",
    "N1", "N2", "N3", "N4", "N5",
    "O1", "O2", "O3", "O4", "O5",
]

DEMOGRAPHIC_VARS = ["gender", "age"]


def _extract_omv_file(omv_path, copy_from_env=None):
    """Extract .omv ZIP archive and return (temp_dir, index_html, extract_dir, file_size).

    The .omv format is a ZIP containing index.html (rendered analysis output),
    data.bin, strings.bin, xdata.json, and meta.
    """
    temp_dir = tempfile.mkdtemp(prefix="omv_efa_verify_")

    # If copy_from_env is available, copy the file from the VM first
    local_omv = os.path.join(temp_dir, "BFI_FactorAnalysis.omv")
    if copy_from_env:
        try:
            copy_from_env(omv_path, local_omv)
        except Exception as e:
            logger.warning(f"copy_from_env failed: {e}, trying local path")
            local_omv = omv_path
    else:
        local_omv = omv_path

    if not os.path.isfile(local_omv):
        raise FileNotFoundError(f"OMV output file not found: {omv_path}")

    file_size = os.path.getsize(local_omv)
    extract_dir = os.path.join(temp_dir, "extracted")
    os.makedirs(extract_dir, exist_ok=True)

    with zipfile.ZipFile(local_omv, "r") as zf:
        zf.extractall(extract_dir)

    # Locate index.html
    index_path = os.path.join(extract_dir, "index.html")
    if not os.path.exists(index_path):
        # Walk the extracted tree
        for root, dirs, files in os.walk(extract_dir):
            if "index.html" in files:
                index_path = os.path.join(root, "index.html")
                break

    if not os.path.exists(index_path):
        raise FileNotFoundError("index.html not found inside .omv archive")

    with open(index_path, "r", encoding="utf-8-sig") as f:
        index_html = f.read()

    return temp_dir, index_html, extract_dir, file_size


def verify_personality_efa(traj, env_info, task_info):
    """
    Verify the personality_efa task.

    Criteria:
      1. (15 pts) File saved at the correct path
      2. (10 pts) Valid .omv structure
      3. (20 pts) EFA analysis present
      4. (15 pts) Correct number of factors (5)
      5. (15 pts) Oblimin rotation used
      6. (15 pts) KMO and Bartlett's test present
      7. (10 pts) Factor loadings show personality items (not gender/age)

    Pass threshold: 70/100
    """
    copy_from_env = env_info.get("copy_from_env")
    score = 0
    feedback_parts = []
    temp_dir = None

    # ==================================================================
    # Output-existence gate
    # ==================================================================
    try:
        temp_dir, index_html, extract_dir, file_size = _extract_omv_file(
            OMV_OUTPUT_FILE, copy_from_env
        )
    except FileNotFoundError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file not found or could not be extracted: {e}",
        }
    except zipfile.BadZipFile:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output file exists but is not a valid ZIP/.omv archive",
        }
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Error accessing output file: {e}",
        }

    try:
        html_lower = index_html.lower()
        logger.info(f"Extracted .omv file: {file_size} bytes, index.html: {len(index_html)} chars")

        # ==============================================================
        # Criterion 1 (15 pts): File saved at the correct path
        # ==============================================================
        try:
            c1_score = 0
            # File exists (already confirmed by extraction above)
            c1_score = 10
            feedback_parts.append(f"File exists: {OMV_OUTPUT_FILE} ({file_size} bytes)")

            # Check file has substantial size (an .omv with EFA results
            # should be at least several KB)
            if file_size >= 10000:
                c1_score = 15
                feedback_parts.append(f"File size substantial: {file_size} bytes")
            elif file_size >= 5000:
                c1_score = 13
                feedback_parts.append(f"File size moderate: {file_size} bytes")
            else:
                feedback_parts.append(f"File size small: {file_size} bytes")

            score += c1_score
            logger.info(f"Criterion 1 (File saved): {c1_score}/15")

        except Exception as e:
            logger.error(f"Criterion 1 error: {e}", exc_info=True)
            feedback_parts.append(f"File saved: verification error ({e})")

        # ==============================================================
        # Criterion 2 (10 pts): Valid .omv structure
        # ==============================================================
        try:
            c2_score = 0

            # Check for expected files in the .omv archive
            has_index = os.path.exists(os.path.join(extract_dir, "index.html"))
            has_meta = os.path.exists(os.path.join(extract_dir, "meta"))
            has_xdata = os.path.exists(os.path.join(extract_dir, "xdata.json"))
            has_data = os.path.exists(os.path.join(extract_dir, "data.bin"))

            if has_index:
                c2_score += 4
            if has_meta:
                c2_score += 2
            if has_xdata:
                c2_score += 2
            if has_data:
                c2_score += 2

            found_components = []
            if has_index:
                found_components.append("index.html")
            if has_meta:
                found_components.append("meta")
            if has_xdata:
                found_components.append("xdata.json")
            if has_data:
                found_components.append("data.bin")

            feedback_parts.append(f"OMV structure: {', '.join(found_components)} ({c2_score}/10)")
            score += c2_score
            logger.info(f"Criterion 2 (Valid OMV): {c2_score}/10")

        except Exception as e:
            logger.error(f"Criterion 2 error: {e}", exc_info=True)
            feedback_parts.append(f"OMV structure: verification error ({e})")

        # ==============================================================
        # Criterion 3 (20 pts): EFA analysis present
        # ==============================================================
        try:
            c3_score = 0

            # Check for EFA-related keywords in the rendered output
            efa_keywords = [
                "factor analysis",
                "exploratory factor analysis",
                "factor loadings",
                "factor loading",
            ]
            found_efa_keywords = []
            for kw in efa_keywords:
                if kw in html_lower:
                    found_efa_keywords.append(kw)

            if found_efa_keywords:
                c3_score += 12
                feedback_parts.append(
                    f"EFA analysis found: keywords [{', '.join(found_efa_keywords)}]"
                )
            else:
                # Check for less specific factor-related keywords
                if "factor" in html_lower:
                    c3_score += 5
                    feedback_parts.append(
                        "EFA: 'factor' keyword found but no specific EFA keywords"
                    )
                else:
                    feedback_parts.append("EFA: no factor analysis keywords found")

            # Check for factor loading values (numeric values in a table)
            # Look for patterns like 0.xxx or -0.xxx that indicate loadings
            loading_pattern = re.findall(
                r'[-−]?0\.\d{2,4}', index_html
            )
            if len(loading_pattern) >= 10:
                c3_score += 8
                feedback_parts.append(
                    f"EFA: {len(loading_pattern)} factor loading values detected"
                )
            elif len(loading_pattern) >= 3:
                c3_score += 4
                feedback_parts.append(
                    f"EFA: {len(loading_pattern)} possible loading values (few)"
                )
            else:
                feedback_parts.append("EFA: no factor loading values detected")

            score += c3_score
            logger.info(f"Criterion 3 (EFA present): {c3_score}/20")

        except Exception as e:
            logger.error(f"Criterion 3 error: {e}", exc_info=True)
            feedback_parts.append(f"EFA analysis: verification error ({e})")

        # ==============================================================
        # Criterion 4 (15 pts): Correct number of factors (5)
        # ==============================================================
        try:
            c4_score = 0

            # Detect factor count from "Factor N" references
            factor_nums = set()
            for m in re.finditer(r'factor\s*(\d+)', html_lower):
                factor_nums.add(int(m.group(1)))

            # Also check for column headers like "Factor 1" through "Factor 5"
            if not factor_nums:
                for m in re.finditer(r'Factor\s+(\d+)', index_html):
                    factor_nums.add(int(m.group(1)))

            if factor_nums:
                max_factor = max(factor_nums)
                if max_factor == 5 and len(factor_nums) >= 5:
                    c4_score = 15
                    feedback_parts.append(
                        f"Factor count: exactly 5 factors detected (Factor 1-5)"
                    )
                elif max_factor == 5:
                    c4_score = 12
                    feedback_parts.append(
                        f"Factor count: max factor is 5 (found references to factors: {sorted(factor_nums)})"
                    )
                elif max_factor > 5:
                    c4_score = 5
                    feedback_parts.append(
                        f"Factor count: {max_factor} factors detected (expected 5)"
                    )
                elif max_factor < 5:
                    c4_score = 5
                    feedback_parts.append(
                        f"Factor count: only {max_factor} factors detected (expected 5)"
                    )
            else:
                # Try another approach: count "Factor" column headers
                # jamovi may render differently
                factor_header_count = len(
                    re.findall(r'(?i)factor\s*\d', index_html)
                )
                if factor_header_count >= 5:
                    c4_score = 10
                    feedback_parts.append(
                        f"Factor count: {factor_header_count} factor header references found"
                    )
                elif factor_header_count > 0:
                    c4_score = 5
                    feedback_parts.append(
                        f"Factor count: {factor_header_count} factor references (may be fewer than 5)"
                    )
                else:
                    feedback_parts.append("Factor count: could not determine number of factors")

            score += c4_score
            logger.info(f"Criterion 4 (5 factors): {c4_score}/15")

        except Exception as e:
            logger.error(f"Criterion 4 error: {e}", exc_info=True)
            feedback_parts.append(f"Factor count: verification error ({e})")

        # ==============================================================
        # Criterion 5 (15 pts): Oblimin rotation used
        # ==============================================================
        try:
            c5_score = 0

            oblimin_keywords = ["oblimin"]
            oblique_keywords = ["oblique"]
            rotation_keywords = ["rotation"]

            has_oblimin = any(kw in html_lower for kw in oblimin_keywords)
            has_oblique = any(kw in html_lower for kw in oblique_keywords)
            has_rotation = any(kw in html_lower for kw in rotation_keywords)

            if has_oblimin:
                c5_score = 15
                feedback_parts.append("Rotation: oblimin detected")
            elif has_oblique and has_rotation:
                c5_score = 10
                feedback_parts.append(
                    "Rotation: oblique rotation detected (oblimin keyword not explicit)"
                )
            elif has_rotation:
                # Check for other rotation methods
                other_rotations = ["varimax", "promax", "quartimax", "equamax"]
                found_other = [r for r in other_rotations if r in html_lower]
                if found_other:
                    c5_score = 3
                    feedback_parts.append(
                        f"Rotation: {', '.join(found_other)} found instead of oblimin"
                    )
                else:
                    c5_score = 5
                    feedback_parts.append(
                        "Rotation: rotation present but type not confirmed as oblimin"
                    )
            else:
                # In jamovi, oblimin may appear in the analysis options but not
                # always in the rendered HTML. Check if the factor structure table
                # has a "structure matrix" or "pattern matrix" header, which
                # indicates oblique rotation was used (orthogonal produces only
                # a single loading matrix without the pattern/structure distinction)
                if "pattern matrix" in html_lower or "structure matrix" in html_lower:
                    c5_score = 10
                    feedback_parts.append(
                        "Rotation: pattern/structure matrix present (indicates oblique rotation)"
                    )
                else:
                    feedback_parts.append("Rotation: no rotation keywords detected")

            score += c5_score
            logger.info(f"Criterion 5 (Oblimin): {c5_score}/15")

        except Exception as e:
            logger.error(f"Criterion 5 error: {e}", exc_info=True)
            feedback_parts.append(f"Rotation: verification error ({e})")

        # ==============================================================
        # Criterion 6 (15 pts): KMO and Bartlett's test present
        # ==============================================================
        try:
            c6_score = 0

            # Check for KMO
            kmo_keywords = ["kmo", "kaiser-meyer-olkin", "kaiser meyer olkin",
                            "sampling adequacy", "measure of sampling"]
            has_kmo = any(kw in html_lower for kw in kmo_keywords)

            # Check for Bartlett's test
            bartlett_keywords = ["bartlett", "sphericity"]
            has_bartlett = any(kw in html_lower for kw in bartlett_keywords)

            if has_kmo and has_bartlett:
                c6_score = 15
                feedback_parts.append("Assumption tests: both KMO and Bartlett's test present")
            elif has_kmo:
                c6_score = 8
                feedback_parts.append("Assumption tests: KMO present, Bartlett's test not found")
            elif has_bartlett:
                c6_score = 8
                feedback_parts.append("Assumption tests: Bartlett's test present, KMO not found")
            else:
                # Check for any adequacy-related terms
                adequacy_keywords = ["adequacy", "suitability", "sampling"]
                has_adequacy = any(kw in html_lower for kw in adequacy_keywords)
                if has_adequacy:
                    c6_score = 3
                    feedback_parts.append(
                        "Assumption tests: some adequacy keywords found but KMO/Bartlett not confirmed"
                    )
                else:
                    feedback_parts.append("Assumption tests: neither KMO nor Bartlett's test found")

            score += c6_score
            logger.info(f"Criterion 6 (KMO/Bartlett): {c6_score}/15")

        except Exception as e:
            logger.error(f"Criterion 6 error: {e}", exc_info=True)
            feedback_parts.append(f"Assumption tests: verification error ({e})")

        # ==============================================================
        # Criterion 7 (10 pts): Factor loadings show personality items
        #                        (not gender/age)
        # ==============================================================
        try:
            c7_score = 0

            # Count personality items appearing in the output
            found_items = []
            for item in PERSONALITY_ITEMS:
                # Use word boundary to avoid partial matches
                if re.search(r'\b' + re.escape(item) + r'\b', index_html):
                    found_items.append(item)

            # Check for demographic variables in the factor loading context
            # (they should NOT appear as analysis variables)
            found_demographics = []
            for var in DEMOGRAPHIC_VARS:
                if re.search(r'\b' + re.escape(var) + r'\b', html_lower):
                    found_demographics.append(var)

            # Scoring: items found
            n_found = len(found_items)
            if n_found >= 20:
                c7_score += 7
                feedback_parts.append(
                    f"Personality items: {n_found}/25 items found in output"
                )
            elif n_found >= 10:
                c7_score += 4
                feedback_parts.append(
                    f"Personality items: {n_found}/25 items found (partial)"
                )
            elif n_found >= 5:
                c7_score += 2
                feedback_parts.append(
                    f"Personality items: only {n_found}/25 items found"
                )
            else:
                feedback_parts.append(
                    f"Personality items: very few items found ({n_found}/25)"
                )

            # Bonus: demographics NOT in factor loadings (correct exclusion)
            if not found_demographics:
                c7_score += 3
                feedback_parts.append(
                    "Demographics: gender/age correctly excluded from analysis"
                )
            else:
                # Demographics present is not necessarily wrong (they could appear
                # in the data view but not in the analysis), so partial penalty
                c7_score += 1
                feedback_parts.append(
                    f"Demographics: {', '.join(found_demographics)} found in output "
                    f"(may be in data, not analysis)"
                )

            score += c7_score
            logger.info(f"Criterion 7 (Items): {c7_score}/10")

        except Exception as e:
            logger.error(f"Criterion 7 error: {e}", exc_info=True)
            feedback_parts.append(f"Personality items: verification error ({e})")

        # ==============================================================
        # Final result
        # ==============================================================
        passed = score >= PASS_THRESHOLD
        feedback = " | ".join(feedback_parts)

        logger.info(
            f"Verification complete: score={score}/100, passed={passed} "
            f"(threshold={PASS_THRESHOLD})"
        )

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
        }

    except Exception as e:
        logger.error(f"Top-level verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {e}",
        }

    finally:
        # Clean up temp directory
        if temp_dir and os.path.isdir(temp_dir):
            try:
                import shutil
                shutil.rmtree(temp_dir, ignore_errors=True)
            except Exception:
                pass
