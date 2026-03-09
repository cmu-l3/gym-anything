# VLM Evaluator Design Guide

## Overview

This document provides guidelines for designing **hybrid verification systems** that combine programmatic checks with VLM-based evaluation. The goal is to create verifiers that accurately assess task completion while being robust against gaming.

**Key Principle:** Use programmatic checks for everything deterministic. Use VLM for semantic/visual understanding that cannot be verified otherwise. Run BOTH in parallel and combine scores.

---

## Verifier Output Format

All verifiers must return a dictionary with this structure:

```python
{
    "passed": bool,           # True if task was completed successfully
    "score": int,             # 0-100, percentage of criteria met
    "feedback": str           # Human-readable feedback with ✅/❌ markers
}
```

---

## When to Use VLM vs Programmatic

The decision depends on what CAN be verified deterministically vs what requires semantic understanding.

### Cross-Domain Examples

| Application | Verification Need | Method | Rationale |
|-------------|-------------------|--------|-----------|
| **GIMP** | Image dimensions changed | Programmatic | Pixel comparison |
| **GIMP** | Gaussian blur applied | Programmatic | Edge sharpness calculation |
| **GIMP** | "Photo looks professional" | VLM | Aesthetic judgment |
| **GIMP** | Specific object removed | VLM | Semantic understanding |
| **VSCode** | File contains specific text | Programmatic | String matching |
| **VSCode** | Code compiles without errors | Programmatic | Run compiler |
| **VSCode** | Code follows best practices | VLM | Style/quality judgment |
| **VSCode** | Refactoring preserved behavior | VLM + Programmatic | Tests + semantic check |
| **Chrome** | Navigated to correct URL | Programmatic | URL pattern matching |
| **Chrome** | Correct form was filled | Programmatic | DOM inspection |
| **Chrome** | Page shows expected content | VLM | Visual verification |
| **Chrome** | Captcha was solved | VLM | Cannot be programmatic |
| **EMR/OpenEMR** | Patient record exists in DB | Programmatic | Database query |
| **EMR/OpenEMR** | All required fields filled | Programmatic | Field validation |
| **EMR/OpenEMR** | Clinical notes are appropriate | VLM | Medical judgment |
| **LibreOffice** | Spreadsheet has N rows | Programmatic | Cell counting |
| **LibreOffice** | Formulas calculate correctly | Programmatic | Value comparison |
| **LibreOffice** | Chart visualizes data properly | VLM | Visual assessment |
| **LibreOffice** | Document formatting is professional | VLM | Aesthetic judgment |
| **Google Earth** | Process is running | Programmatic | PID check |
| **Google Earth** | Coordinates within tolerance | Programmatic | Haversine distance |
| **Google Earth** | Specific landmark visible | VLM | Visual recognition |
| **Google Earth** | Measurement tool was used | VLM (trajectory) | Action recognition |
| **DICOM Viewer** | Correct study loaded | Programmatic | DICOM metadata |
| **DICOM Viewer** | Annotation placed correctly | Programmatic | Coordinate check |
| **DICOM Viewer** | Abnormality identified | VLM | Medical imaging |

---

## VLM Evaluation Design

### Core Concept: Multi-Question Evaluation

For each task, design **multiple independent questions** that check different aspects. Each question contributes to the final score. This approach:
- Reduces single-point-of-failure risk
- Provides granular feedback
- Makes gaming harder (must fool multiple checks)

### Example Question Types

The following are **examples** of question types you might use. This is NOT an exhaustive list—design questions appropriate for your specific task.

#### Type A: Final State Check
Provide the final screenshot and ask about task completion.

```yaml
context: final_screenshot
question: "Is the Eiffel Tower in Paris visible in this Google Earth view?"
```

#### Type B: Before/After Comparison
Provide first and last screenshots to detect changes.

```yaml
context: [first_screenshot, final_screenshot]
question: "Was a new placemark icon added between these two images?"
```

#### Type C: Extracted Data Validation
Use OCR or other extraction first, then have VLM validate.

```yaml
context: ocr_text + expected_value
question: "The OCR extracted '48.85° N, 2.29° E'. Are these coordinates near Paris, France?"
```

#### Type D: Trajectory/Workflow Check
Sample frames from trajectory to verify process was followed.

```yaml
context: [frame_0, frame_25pct, frame_50pct, frame_75pct, frame_100pct]
question: "Did the agent open the Ruler tool and draw a measurement line?"
```

#### Type E: Negative/Adversarial Check
Ask what could be WRONG to catch gaming attempts.

```yaml
context: final_screenshot
question: "Could this be a different tower (Tokyo Tower, Las Vegas replica) rather than the real Eiffel Tower?"
```

#### Type F: UI State Verification
Verify the application is in expected state.

```yaml
context: final_screenshot
question: "Is Google Earth's main 3D view visible (not a dialog, not Street View, not an error)?"
```

**Design your own question types based on what your task requires.**

---

## Scoring and Feedback

### Standard Pattern

Follow the pattern used throughout the codebase:

```python
def verify_task(traj, env_info, task_info):
    """
    Verify task completion using hybrid programmatic + VLM checks.
    """
    feedback_parts = []
    criteria_met = 0
    total_criteria = 0  # Count as you add criteria

    # =================================================================
    # PROGRAMMATIC CHECKS
    # =================================================================

    # Criterion 1: Process running
    total_criteria += 1
    if is_process_running("google-earth"):
        criteria_met += 1
        feedback_parts.append("✅ Google Earth is running")
    else:
        feedback_parts.append("❌ Google Earth is not running")

    # Criterion 2: File exists
    total_criteria += 1
    if file_exists("/path/to/result.png"):
        criteria_met += 1
        feedback_parts.append("✅ Result file created")
    else:
        feedback_parts.append("❌ Result file not found")

    # Criterion 3: Coordinates valid (example with partial credit)
    total_criteria += 1
    coords = extract_coordinates()
    if coords and within_tolerance(coords, target, 0.01):
        criteria_met += 1
        feedback_parts.append(f"✅ Coordinates correct: {coords}")
    elif coords:
        criteria_met += 0.5  # Partial credit
        feedback_parts.append(f"⚠️ Coordinates extracted but off target: {coords}")
    else:
        feedback_parts.append("❌ Could not extract coordinates")

    # =================================================================
    # VLM CHECKS (run in parallel with programmatic, not gated)
    # =================================================================

    # Criterion 4: Landmark visible (VLM)
    total_criteria += 1
    vlm_response = query_vlm(
        image=final_screenshot,
        prompt="Is the Eiffel Tower clearly visible? Answer: Yes/No"
    )
    if vlm_response.get("landmark_visible"):
        criteria_met += 1
        feedback_parts.append("✅ Eiffel Tower visible in view")
    else:
        feedback_parts.append("❌ Eiffel Tower not visible")

    # Criterion 5: Zoom level appropriate (VLM)
    total_criteria += 1
    vlm_response = query_vlm(
        image=final_screenshot,
        prompt="Is the view zoomed in enough to clearly see the landmark (not showing all of Europe)?"
    )
    if vlm_response.get("zoom_appropriate"):
        criteria_met += 1
        feedback_parts.append("✅ Appropriate zoom level")
    else:
        feedback_parts.append("⚠️ View may be too zoomed out")

    # Criterion 6: Negative check (VLM)
    total_criteria += 1
    vlm_response = query_vlm(
        image=final_screenshot,
        prompt="Could this be a replica or different location (Las Vegas, Tokyo Tower)?"
    )
    if not vlm_response.get("possibly_wrong_location"):
        criteria_met += 1
        feedback_parts.append("✅ Location appears authentic")
    else:
        feedback_parts.append("⚠️ Possible wrong location detected")

    # =================================================================
    # CALCULATE FINAL SCORE
    # =================================================================

    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70  # Threshold depends on task difficulty

    # Add summary
    if passed and score >= 90:
        feedback_parts.append("🎉 Excellent task completion!")
    elif passed:
        feedback_parts.append("✅ Task completed successfully")
    else:
        feedback_parts.append("❌ Task not completed")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
```

### Weighting Criteria

If some criteria are more important than others, use weighted scoring:

```python
criteria = {
    'process_running': {'met': True, 'weight': 0.1},    # Required but low weight
    'file_created': {'met': True, 'weight': 0.1},
    'coordinates_correct': {'met': True, 'weight': 0.2},
    'landmark_visible_vlm': {'met': True, 'weight': 0.3},  # Most important
    'zoom_appropriate_vlm': {'met': False, 'weight': 0.15},
    'authentic_location_vlm': {'met': True, 'weight': 0.15},
}

score = sum(c['weight'] * 100 if c['met'] else 0 for c in criteria.values())
# score = 10 + 10 + 20 + 30 + 0 + 15 = 85
```

---

## VLM Limitations and How to Handle Them

### 1. Poor Small Text Recognition

**Problem:** VLMs struggle with small text in status bars, dialogs, coordinates.

**Solution:** Use OCR (Tesseract) for text extraction, then optionally have VLM validate the extracted text.

```python
# WRONG: Ask VLM to read coordinates from status bar
vlm_result = query_vlm(image, "What coordinates are shown in the status bar?")

# RIGHT: OCR first, then VLM validates
ocr_text = tesseract_ocr(crop_status_bar(screenshot))
# Use ocr_text directly in programmatic check, or:
vlm_result = query_vlm(
    text=f"OCR extracted: '{ocr_text}'. Does this look like coordinates near Paris?",
    image=cropped_region  # Optional: enlarged crop
)
```

### 2. Spatial Reasoning Limitations

**Problem:** VLMs may confuse similar-looking landmarks or locations.

**Solution:** Ask for distinctive features and include negative examples.

```python
# WRONG: Vague question
prompt = "Is this the Eiffel Tower?"

# RIGHT: Ask for specific distinguishing features
prompt = """
Is this the Eiffel Tower in Paris? Check for:
1. Iron lattice structure (not solid)
2. Tapering shape wider at base
3. Parisian urban context (Seine River, Champ de Mars)

This is NOT:
- Tokyo Tower (red and white painted)
- Las Vegas Eiffel (shorter, casino context)
- Blackpool Tower (different proportions)

Answer each point.
"""
```

### 3. Positive/Negative Response Bias

**Problem:** VLMs may default to "yes" or "no" without careful analysis.

**Solution:** Require evidence and use inverse questions.

```python
# WRONG: Single yes/no
prompt = "Did the agent complete the task?"

# RIGHT: Multiple questions requiring evidence
prompts = [
    "What landmark is visible in this image? Name it specifically.",
    "What visual features identify this as [landmark]?",
    "What evidence suggests this might NOT be the correct location?",
    "Rate your confidence: Low/Medium/High"
]
```

### 4. Context Length and Cost

**Problem:** Full trajectory may be 100+ frames, expensive to process.

**Solution:** Sample key frames strategically.

```python
# Sample frames for trajectory analysis
def sample_trajectory(trajectory, num_samples=5):
    n = len(trajectory.frames)
    indices = [
        0,                    # Start
        n // 4,              # 25%
        n // 2,              # 50%
        3 * n // 4,          # 75%
        n - 1                # End
    ]
    return [trajectory.frames[i] for i in indices]

# Or detect significant changes programmatically
def detect_key_frames(trajectory, ssim_threshold=0.85):
    key_frames = [trajectory.frames[0]]
    for i in range(1, len(trajectory.frames)):
        if ssim(trajectory.frames[i], key_frames[-1]) < ssim_threshold:
            key_frames.append(trajectory.frames[i])
    return key_frames[:10]  # Cap at 10 frames
```

### 5. Inconsistent Output Format

**Problem:** VLM may not follow requested JSON format.

**Solution:** Request structured output and parse robustly.

```python
prompt = """
Evaluate this screenshot. Respond ONLY in this JSON format:
{
  "landmark_visible": true/false,
  "landmark_name": "string",
  "confidence": "low"/"medium"/"high"
}
"""

def parse_vlm_response(response_text):
    # Try JSON parsing
    try:
        import json
        # Find JSON in response (may have extra text)
        match = re.search(r'\{.*\}', response_text, re.DOTALL)
        if match:
            return json.loads(match.group())
    except:
        pass

    # Fallback: heuristic extraction
    result = {}
    if 'yes' in response_text.lower() or 'true' in response_text.lower():
        result['landmark_visible'] = True
    elif 'no' in response_text.lower() or 'false' in response_text.lower():
        result['landmark_visible'] = False

    return result
```

---

## Domain-Specific Examples

### GIMP: Verify Gaussian Blur Applied

```python
def verify_gaussian_blur(traj, env_info, task_info):
    feedback_parts = []
    criteria_met = 0
    total_criteria = 5

    # Load images
    original = load_image(original_path)
    result = load_image(result_path)

    # Programmatic: Edge sharpness reduction
    orig_sharpness = calculate_edge_sharpness(original)
    result_sharpness = calculate_edge_sharpness(result)
    reduction = (orig_sharpness - result_sharpness) / orig_sharpness

    if 0.40 <= reduction <= 0.70:
        criteria_met += 1
        feedback_parts.append(f"✅ Sharpness reduced by {reduction:.0%}")
    else:
        feedback_parts.append(f"❌ Sharpness reduction {reduction:.0%} (expected 40-70%)")

    # Programmatic: Uniform blur application
    uniformity = analyze_blur_uniformity(original, result)
    if uniformity > 0.7:
        criteria_met += 1
        feedback_parts.append("✅ Blur applied uniformly")
    else:
        feedback_parts.append("❌ Blur not uniform across image")

    # Programmatic: Image quality preserved
    mse = calculate_mse(original, result)
    if 10 < mse < 5000:
        criteria_met += 1
        feedback_parts.append("✅ Image quality maintained")
    else:
        feedback_parts.append("❌ Image quality degraded")

    # Programmatic: Images different
    if not np.array_equal(original, result):
        criteria_met += 1
        feedback_parts.append("✅ Image was modified")
    else:
        feedback_parts.append("❌ Image unchanged")

    # VLM: Blur looks natural (optional quality check)
    vlm_result = query_vlm(
        images=[original, result],
        prompt="Compare these images. Does the second have a natural-looking Gaussian blur applied (soft, smooth edges) rather than artifacts or distortion?"
    )
    if vlm_result.get("natural_blur"):
        criteria_met += 1
        feedback_parts.append("✅ Blur appears natural")
    else:
        feedback_parts.append("⚠️ Blur may have artifacts")

    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75

    return {"passed": passed, "score": score, "feedback": " | ".join(feedback_parts)}
```

### VSCode: Verify Code Refactoring

```python
def verify_refactoring(traj, env_info, task_info):
    feedback_parts = []
    criteria_met = 0
    total_criteria = 4

    # Programmatic: File was modified
    original_content = read_original()
    modified_content = read_from_env(copy_from_env, file_path)

    if original_content != modified_content:
        criteria_met += 1
        feedback_parts.append("✅ File was modified")
    else:
        feedback_parts.append("❌ File unchanged")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Programmatic: Syntax valid (code compiles/parses)
    try:
        ast.parse(modified_content)
        criteria_met += 1
        feedback_parts.append("✅ Valid Python syntax")
    except SyntaxError as e:
        feedback_parts.append(f"❌ Syntax error: {e}")

    # Programmatic: Tests pass
    test_result = run_tests()
    if test_result.passed:
        criteria_met += 1
        feedback_parts.append(f"✅ All {test_result.count} tests pass")
    else:
        feedback_parts.append(f"❌ {test_result.failed} tests failing")

    # VLM: Refactoring follows requested pattern
    vlm_result = query_vlm(
        text=f"Original:\n{original_content}\n\nModified:\n{modified_content}",
        prompt="Was the function extracted into a separate helper as requested? Did the refactoring follow DRY principles?"
    )
    if vlm_result.get("follows_pattern"):
        criteria_met += 1
        feedback_parts.append("✅ Refactoring follows requested pattern")
    else:
        feedback_parts.append("⚠️ Refactoring may not match requirements")

    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75

    return {"passed": passed, "score": score, "feedback": " | ".join(feedback_parts)}
```

### OpenEMR: Verify Patient Registration

```python
def verify_patient_registration(traj, env_info, task_info):
    feedback_parts = []
    score = 0

    # Programmatic: Query database directly
    patient = db.get_patient_by_name("Brown", "Michael")

    if not patient:
        return {"passed": False, "score": 0, "feedback": "❌ Patient not found in database"}

    # Programmatic: Check each field (weighted)
    if patient['fname'] == 'Michael' and patient['lname'] == 'Brown':
        score += 10
        feedback_parts.append("✅ Name correct")
    else:
        feedback_parts.append("❌ Name incorrect")

    if patient['DOB'] == '1992-04-10':
        score += 10
        feedback_parts.append("✅ DOB correct")
    else:
        feedback_parts.append(f"❌ DOB incorrect: {patient['DOB']}")

    if patient['sex'].lower() in ['male', 'm']:
        score += 10
        feedback_parts.append("✅ Gender correct")

    # ... more programmatic field checks ...

    # VLM: Check if clinical notes are appropriate (if applicable)
    if patient.get('notes'):
        vlm_result = query_vlm(
            text=patient['notes'],
            prompt="Are these clinical notes professionally written and medically appropriate?"
        )
        if vlm_result.get("appropriate"):
            score += 10
            feedback_parts.append("✅ Clinical notes appropriate")

    passed = score >= 75
    return {"passed": passed, "score": score, "feedback": " | ".join(feedback_parts)}
```

### Chrome: Verify Form Submission

```python
def verify_form_submission(traj, env_info, task_info):
    feedback_parts = []
    criteria_met = 0
    total_criteria = 4

    # Programmatic: Check final URL
    final_url = read_file("/tmp/final_url.txt")
    if "confirmation" in final_url or "success" in final_url:
        criteria_met += 1
        feedback_parts.append("✅ Reached confirmation page")
    else:
        feedback_parts.append(f"❌ Not on confirmation page: {final_url}")

    # Programmatic: Check submitted form data (if logged)
    form_data = read_json("/tmp/form_data.json")
    if form_data.get("email") == "test@example.com":
        criteria_met += 1
        feedback_parts.append("✅ Email field correct")

    # VLM: Verify confirmation message visible
    vlm_result = query_vlm(
        image=final_screenshot,
        prompt="Is there a confirmation message visible (e.g., 'Thank you', 'Submission successful', 'Your order has been placed')?"
    )
    if vlm_result.get("confirmation_visible"):
        criteria_met += 1
        feedback_parts.append("✅ Confirmation message visible")
    else:
        feedback_parts.append("❌ No confirmation message found")

    # VLM: Check for error messages (negative check)
    vlm_result = query_vlm(
        image=final_screenshot,
        prompt="Are there any error messages visible (red text, 'Error', 'Failed', 'Invalid')?"
    )
    if not vlm_result.get("errors_visible"):
        criteria_met += 1
        feedback_parts.append("✅ No error messages")
    else:
        feedback_parts.append("❌ Error messages visible")

    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75

    return {"passed": passed, "score": score, "feedback": " | ".join(feedback_parts)}
```

---

## Anti-Gaming Considerations

VLM evaluation is harder to game than keyword matching, but consider these attacks:

| Attack | Mitigation |
|--------|------------|
| Agent displays a photo of target instead of navigating | Check application UI elements are visible, verify process integrity |
| Agent manipulates files directly | Verify through UI state, not just file contents |
| Agent navigates to lookalike location | Include negative checks asking about replicas/alternatives |
| Agent uses cached/pre-made screenshots | Check trajectory shows actual interaction, verify timestamps |
| Agent types keywords to trigger OCR matches | Use visual VLM checks, not just text-based |

**Best defense: Combine multiple independent verification methods. An agent would need to fool ALL of them.**

---

## Critical Lessons Learned

These lessons come from real-world experience designing verifiers for Google Earth and similar complex desktop applications.

### 1. Read the Task Description Carefully

**The verifier should match EXACTLY what the task asks—not more, not less.**

```yaml
# Task says: "Navigate to the Eiffel Tower in Paris"
#
# WRONG verifier assumptions:
#   - Requires specific zoom level
#   - Requires 3D view enabled
#   - Requires tower to be "clearly visible" with "iron lattice structure"
#   - Requires specific coordinates visible in status bar
#
# RIGHT verifier:
#   - Any view showing Paris / Eiffel Tower area is acceptable
#   - Wide view showing Paris OR close-up are both valid
#   - Task didn't specify zoom, 3D mode, or visibility requirements
```

### 2. Understand Setup Scripts BEFORE Designing Verification

**Setup scripts establish the initial state. Don't verify what setup guarantees.**

```bash
# Example setup script:
pkill -f google-earth-pro  # Kill any existing
google-earth-pro &         # Start fresh
wmctrl -r "Google Earth" -b add,fullscreen  # Fullscreen
```

```python
# WRONG: Redundant check (setup already guarantees this)
if not is_google_earth_running():
    return {"passed": False, "feedback": "Google Earth not running"}

# RIGHT: Skip process checks entirely—focus on task-specific verification
```

### 3. Match VLM Prompts to Actual Task Requirements

**Don't add constraints the task didn't specify.**

```python
# Task: "Navigate to the Golden Gate Bridge"

# WRONG prompt (over-constrained):
"""
Is the Golden Gate Bridge visible with:
- Iconic orange-red color
- Two towers with suspension cables
- San Francisco Bay and Marin County visible
- Zoomed in to see the bridge structure clearly
"""

# RIGHT prompt (matches task):
"""
Does this show the Golden Gate Bridge area in San Francisco?
The task doesn't require a specific zoom level. A wide view showing
the SF Bay Area OR a close-up of the bridge are both acceptable.
"""
```

### 4. Use Baseline Comparison for State-Change Tasks

**For tasks that modify application state, compare against baseline saved by setup.**

```bash
# Setup script saves baseline:
cp /home/user/.app/config.xml /tmp/baseline_config.xml
```

```python
# Verifier compares to baseline:
def find_new_items(baseline_content, current_content):
    baseline_items = parse_items(baseline_content)
    current_items = parse_items(current_content)
    return current_items - baseline_items  # Set difference
```

**Google Earth example:**
- `create_placemark` task: Setup saves baseline `myplaces.kml`, verifier compares to find NEW placemarks
- `measure_distance` task: Ruler tool doesn't save to KML—must use VLM-only

### 5. Avoid Unreliable Extraction Methods

**Some data cannot be reliably extracted programmatically.**

| Method | Reliability | Use Case |
|--------|-------------|----------|
| File system changes | High | Screenshots, saved files |
| Application config files | High | Settings, placemarks (KML) |
| Database queries | High | EMR, web apps with DB |
| Clipboard extraction | Low | Coordinates often not there |
| Status bar OCR | Low | Small text, varies by zoom |
| Window title parsing | Medium | May not reflect current state |
| X11 window properties | Low | Invasive, unreliable |

### 6. VLM-Only Is Sometimes the Right Answer

**Some tasks can ONLY be verified via VLM—and that's okay.**

```python
# Task: "Navigate to Mount Everest"
#
# Programmatic options:
#   - Extract coordinates from status bar? (Unreliable OCR)
#   - Parse KML file? (Navigation doesn't write to KML)
#   - Check clipboard? (Coordinates not automatically copied)
#   - Use xdotool to read window state? (Invasive, fragile)
#
# Answer: VLM-only verification
#   - Is this Google Earth?
#   - Does it show the Himalayas / Mount Everest region?
#   - That's it. No need for precise coordinate verification.
```

### 7. File System Changes Are Reliable Signals

**For output-producing tasks, check the file system.**

```python
# Task: "Save a screenshot to the Desktop"

# Setup cleans Desktop:
rm -f /home/user/Desktop/*.jpg /home/user/Desktop/*.png

# Verifier: Any new image file is from the task
def find_new_images(search_dirs, max_age_seconds=300):
    # Find images created during task window
    # This is reliable—setup guaranteed clean state
```

### 8. Hybrid Verification Pattern

**Most tasks need both programmatic and VLM verification.**

```
┌─────────────────────────────────────────────────────────────┐
│                        Task Type                             │
├─────────────────────────────────────────────────────────────┤
│  Creates output file?  ─────> Check file exists + VLM content│
│  Modifies app state?   ─────> Baseline diff + VLM confirmation│
│  Pure navigation?      ─────> VLM-only (no reliable signal)  │
│  Tool usage (ruler)?   ─────> VLM-only (tool state transient) │
└─────────────────────────────────────────────────────────────┘
```

### 9. Scoring Should Reflect What Matters

**Weight criteria based on task requirements, not verification convenience.**

```python
# Task: "Create a placemark named 'Golden Gate Bridge' at the Golden Gate Bridge"
#
# Primary criterion: New placemark created with correct name and location
# Secondary criterion: VLM confirms view shows the area

score = 0
if kml_shows_correct_placemark:
    score += 60  # This is what the task asked for
if vlm_confirms_location:
    score += 40  # Supporting evidence

passed = kml_shows_correct_placemark or (score >= 60)
```

### 10. Summary of Google Earth Verifier Patterns

| Task | Verification Method | Why |
|------|---------------------|-----|
| `navigate_to_location` | VLM-only | No file output, coordinates unreliable |
| `search_coordinates` | VLM-only | Same as navigation |
| `measure_distance` | VLM-only | Ruler tool transient, doesn't save to KML |
| `create_placemark` | KML diff + VLM | Setup saves baseline, placemarks saved to KML |
| `take_screenshot` | File check + VLM | Setup cleans Desktop, image file is output |

---

## Checklist for Verifier Designers

Before finalizing your verifier:

- [ ] **Read task.json carefully**—verify exactly what's asked, nothing more
- [ ] **Read setup_task.sh**—understand initial state and what's guaranteed
- [ ] **Skip redundant checks**—don't verify what setup guarantees
- [ ] **VLM prompts match task**—don't add constraints task didn't specify
- [ ] Programmatic checks cover all deterministic aspects
- [ ] VLM prompts are specific with clear success criteria
- [ ] Negative/adversarial checks included where appropriate
- [ ] Output format is structured (JSON) with fallback parsing
- [ ] Score calculation uses weighted criteria
- [ ] Feedback uses ✅/❌ markers and is actionable
- [ ] VLM limitations addressed (no small text reading, etc.)
- [ ] Multiple independent signals required for success
- [ ] Gaming scenarios considered and mitigated
- [ ] Threshold for `passed` is appropriate for task difficulty
