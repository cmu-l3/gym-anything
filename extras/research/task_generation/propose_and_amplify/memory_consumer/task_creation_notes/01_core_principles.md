> **Note:** This file was generated against an earlier version of the gym-anything
> library. Some paths (e.g. `gym_anything/runners/...`, `examples/<env>/...`,
> `constants.py`) and APIs (e.g. `env.verify()`, `env._runner.ssh_port`) referenced
> below may have moved or been renamed. Cross-check against the current source tree
> (`src/gym_anything/...`, `benchmarks/cua_world/environments/...`,
> `env.get_session_info()`) before relying on any path or import here.

# Core Principles for Task Creation

## Overview

Tasks are the heart of the Gym-Anything benchmark. A well-designed task tests meaningful AI agent capabilities while being robust against adversarial shortcuts. This document establishes the foundational principles that MUST guide every task you create.

---

## START HERE: What Does a Genuinely Hard Task Look Like?

Before reading the principles, internalize this: **most tasks you naturally think of will be too easy.** The first idea is almost always a single-workflow, single-feature operation — the kind of thing any user figures out in their first hour with software. That is not a hard task.

### The litmus test

Ask yourself: **"Could a competent professional who has never used this specific software complete this task in under 10 minutes by clicking around?"** If yes, the task is too easy.

### What makes a task genuinely hard

Hard tasks require the agent to:

1. **Discover what's wrong before fixing it** — The agent is not told which records have errors, only that errors exist. It must scan, evaluate, and identify problems independently.

2. **Chain multiple unrelated features** — The task requires using 3+ distinct capabilities of the application that don't obviously go together (e.g., search + metadata editing + export + tag management), where failure in any one prevents full completion.

3. **Make judgment calls** — The agent must evaluate options and make a decision: which of two conflicting metadata sources is correct? How should items be classified when the boundary is ambiguous?

4. **Complete interdependent subtasks in the right order** — The output of subtask A is required input for subtask B, which enables subtask C. The agent must reason about dependencies.

5. **Handle realistic messiness** — The starting state has multiple inconsistencies of different types (not all of the same kind), mimicking what real imported/accumulated data looks like.

### What does NOT make a task hard

- More UI clicks on a single workflow (exporting a file is still easy even if it's 8 clicks)
- Being told which records to fix and what the correct values are (that's a recipe, not a task)
- Requiring the agent to type a longer string
- Having a stricter pass threshold

### The self-check question

Before finalizing any hard/very_hard task, ask: **"If I removed all the UI instructions from the description, would this task still require significant reasoning and multi-feature knowledge to complete?"** If the answer is no — if it would just be a slightly harder scavenger hunt — redesign the task.

---

## Principle 1: Real-World Relevance

**Tasks must reflect actual professional workflows.**

### Why This Matters
- Agents should learn skills transferable to real-world applications
- Synthetic or contrived tasks don't test practical competence
- Domain experts should recognize the task as legitimate work

### How to Apply
- Research how professionals actually use the software
- Consult documentation, tutorials, and real-world use cases
- Ask: "Would a professional ever need to do this task?"
- Ask: "Does this task require the kind of judgment a professional would exercise, or just mechanical execution?"

---

## Principle 2: Real Data — No Exceptions

**All task data MUST be real. Never use synthetic, generated, simulated, or fabricated data.**

This is non-negotiable. Do not generate data with scripts. Do not create fake records. Do not synthesize files with code. Do not use random noise as a stand-in for real observations. If the data did not come from a real source — a real database, a real file, a real dataset, a real observation — it is not acceptable.

### Why This Matters
- Synthetic data is fake. It does not have the structure, artifacts, edge cases, or complexity of real data. An agent trained or evaluated on synthetic data learns nothing transferable.
- Real data has patterns that no generator can replicate — correlations between fields, realistic outliers, domain-specific formatting, historical artifacts.
- If you generate data with a script, you are testing the agent's ability to process *your script's output*, not its ability to handle real-world data. That is worthless as a benchmark.
- Verifiers need real ground truth to check against — not ground truth that you invented.

### How to Apply
- **Use existing data in the environment.** Query the database. Browse the filesystem. Find what is already there.
- **Use real datasets from the domain.** If the environment needs input files (images, CSVs, audio, FITS files, DICOM scans, etc.), find and use real ones from public repositories, sample data bundled with the software, or standard benchmark datasets.
- **Ship real data files in a `data/` directory** if the environment doesn't come with enough built-in data. Download real datasets and include them.
- **Document the ground truth** from the real data in task metadata.
- **NEVER write a script that generates data** — not with Python, not with astropy, not with numpy, not with any tool. If you find yourself writing `np.random` or `fake.name()` or any data generation code in a setup script, stop. You are doing it wrong. Go find real data instead.

### Acceptable Special Case: Published Aggregate Statistics as Database Records

When real individual-level data is not available for download (e.g., surveillance data that is published only as annual report tables), it is acceptable to create a database by hardcoding **exact values from published sources** — provided:

1. **Every single value** comes directly from a named, citable publication (journal article, government annual report, official statistics release)
2. **No randomness** is applied — no `Get-Random`, no `random.uniform()`, no noise, no interpolation. The numbers in your script must be the exact numbers that appear in the source document.
3. **The source is documented** in the setup script comments and README (URL, publication name, year)
4. **The data is aggregate** — these are published summary statistics, not fabricated individual records

**What is acceptable**:
```powershell
# Real CDC FoodNet 2019 Annual Summary: Enteritidis, California site, all ages
# Source: https://www.cdc.gov/foodnet/reports/annual-reports-2020.html, Table 2
$conn.Execute("INSERT INTO Cases (Year, Serotype, Site, CaseCount, Rate) VALUES (2019, 'Enteritidis', 'CA', 412, 2.08)")
```

**What is NOT acceptable**:
```powershell
# WRONG: adding random noise to real base rates
$noise = (Get-Random -Minimum 85 -Maximum 115) / 100.0
$rate = [math]::Round($baseRate * $noise, 2)  # This is synthetic data!
```

**The key distinction**: Hardcoding 412 because the CDC published 412 is using real data. Hardcoding 412 ± random noise is fabricating data. When in doubt, if the exact value cannot be found in a published source, it is synthetic.

### Acceptable Special Case: Programmatically Constructed Task Scaffolding for Debugging/Repair Tasks

Error-injection debugging tasks (see "Design pattern: Error Injection" above) require `setup_task.sh` to provide a *broken starting artifact* — a broken experiment file, a corrupted config, a syntactically-invalid source file — that the agent must diagnose and repair. If no pre-existing real artifact of the right type exists in the environment, the task creator must construct this starting artifact programmatically.

**This is NOT a violation of the no-synthetic-data rule**, provided all four conditions are met:

1. **The artifact format matches the real application's format exactly.** The constructed file must parse successfully with the same parser the real application uses. It is not a simplified stub — it must be a structurally complete, correctly-typed application artifact.

2. **All domain-content values come from published or documented sources.** Stimulus words, physical constants, parameter values, field names, and identifiers must be real — sourced from published protocols, application documentation, or real-world standards. Randomly invented values are forbidden.

3. **The only programmatically-generated aspects are structure and injected errors.** The scaffolding (XML tags, JSON keys, function skeletons) may be constructed. The content within the scaffolding must be real. The errors injected are the same errors a domain expert would recognize as mistakes (wrong variable name, wrong block order, assignment instead of comparison).

4. **The scaffolding is documented in task.json metadata.** List every injected error explicitly so verifier authors and test writers know the ground truth without reading `setup_task.sh`.

**What is NOT acceptable even for scaffolding**:
- Random or arbitrary content in any field (random letters as stimulus words, random numbers as parameter values, placeholder text like "TODO" or "foo")
- A stripped-down format that doesn't match what the real application produces

**The key test**: If a domain expert looked at the constructed starting artifact without knowing it was programmatically generated, would they recognize it as a plausible (if broken) real file from a real professional workflow? If yes, the scaffolding is acceptable.

### Data Discovery Process
1. Query the environment's database or filesystem to understand available data
2. If built-in data is insufficient, find real datasets from public sources (government data portals, academic repositories, software sample data, standard benchmark datasets)
3. Select subjects with appropriate characteristics for the task
4. Document all relevant IDs, names, conditions in metadata
5. Verify the data actually exists before finalizing the task

### Data Diversity Across Tasks

**Each task in an environment must start from a distinct, meaningfully different state.** If all tasks share the same base dataset, an agent that has run one task has already seen the full environment — eliminating the challenge and diversity of the benchmark.

**What to vary per task:**
- The *records present* (different items, subjects, categories)
- The *initial configuration* (settings, preferences, filters already applied)
- The *organizational structure* (different collections, folders, tags pre-created)
- The *quantity and domain* of data

**Minimum bar:** At least half the tasks in an environment should have meaningfully different records/content from each other. Shared app version and schema is fine; shared *content* is not.

### Feature Diversity Across Tasks

**Each task must exercise a meaningfully different combination of the application's features.** Data diversity alone is insufficient — if all five tasks use the same two features (e.g., "enter a name" and "add contacts"), they test the same narrow capability regardless of how different the names or contacts are.

**The feature matrix check:** Before finalizing your 5 tasks, draw a grid with tasks as rows and application features as columns. Check off which features each task exercises. Red flags:
- Any single feature appearing in all 5 tasks (over-reliance on one feature)
- Any feature appearing in 0 tasks (unexplored capability)
- All tasks using the same 2-3 features with identical structure (homogeneous task set)

**Example of a BAD feature distribution** (all tasks use the same 2 features):
| Task | Name Entry | Add Contacts | Position | Airports | Personalization |
|------|-----------|-------------|----------|----------|----------------|
| Task 1 | ✓ | ✓ | | | |
| Task 2 | ✓ | ✓ | | | |
| Task 3 | ✓ | ✓ | | | |
| Task 4 | ✓ | ✓ | | | |
| Task 5 | ✓ | ✓ | | | |

**Example of a GOOD feature distribution** (each task uses a distinct combination):
| Task | Name Entry | Add Contacts | Position | Airports | Personalization |
|------|-----------|-------------|----------|----------|----------------|
| Task 1 | ✓ | ✓ | ✓ | ✓ | |
| Task 2 | ✓ | ✓ | | ✓ | |
| Task 3 | ✓ | | ✓ | ✓ | ✓ |
| Task 4 | ✓ | ✓ | | ✓ | |
| Task 5 | ✓ | ✓ | | ✓ | ✓ |

**Why this matters for task design:** If you do not explicitly audit feature coverage, you will naturally gravitate to whichever feature was first in the example task or first in your exploration. The result is a benchmark where every task tests the same thing, agents get full credit by learning one pattern, and entire application feature areas go untested.

**Minimum bar:** Each task should use at least 3 distinct features, and no single feature combination should appear in more than 2 of the 5 tasks.

---

## Principle 3: Strong Verifiability

**Every task must have unambiguous, programmatic verification.**

### Why This Matters
- Manual evaluation doesn't scale
- Subjective criteria lead to inconsistent benchmarking
- Agents can game vague success criteria

### Requirements for Strong Verification
1. **Measurable outcomes**: Numeric values, database records, file existence
2. **Ground truth comparison**: Expected values documented before task starts
3. **Multiple verification signals**: Don't rely on a single check
4. **Clear pass/fail criteria**: No ambiguity about success

### Verification pattern (abstract)
A strong verifier checks:
- That the target entity is correct (not a different record)
- That new work was done relative to baseline (not pre-existing data)
- That specific values match expectations (not just "something exists")
- That all required subtasks were completed (partial scoring for each)

---

## Principle 4: Adversarial Robustness

**Tasks must be resistant to gaming and shortcuts.**

### Why This Matters
- Agents will find unintended shortcuts if they exist
- Pre-existing data can be claimed as task completion
- Wrong-target actions should always fail

### Anti-Gaming Patterns

#### Pattern 1: Baseline Recording
Record initial state so you can detect NEW work. Save initial counts, IDs, and timestamps to `/tmp/initial_*` files before the agent starts.

#### Pattern 2: Wrong-Target Rejection
If any action affects the wrong entity (wrong patient, wrong document, wrong record), return score=0 immediately regardless of what else was done correctly.

#### Pattern 3: Timestamp Validation
For tasks where recency matters, verify work was done after the task started, not just that it exists.

#### Pattern 4: Specificity Requirements
Require specific values, not just "something exists". Check the actual content, not just presence.

---

## Principle 5: Appropriate Complexity

**Tasks should test meaningful capabilities without being impossible.**

### Complexity Spectrum

| Level | Characteristics | What the description gives the agent |
|-------|-----------------|--------------------------------------|
| Easy | Single action, obvious UI element | Full UI path spelled out |
| Medium | Multi-step, single workflow | Goal + general approach |
| Hard | Multiple independent subtasks, requires exploration | Goal + what success looks like — NO UI path |
| Very Hard | Multi-feature, requires discovery + judgment across app areas | Goal only — agent must figure out everything |

**Step count is NOT a reliable proxy for difficulty.** A task with 30 UI clicks that are all spelled out is easier than a task with 10 clicks the agent must discover independently.

### What actually makes a task hard

The difficulty of a task comes from how much the agent must **figure out on its own**:

- **Discovery burden**: Does the agent have to find which records need fixing, or are they named explicitly?
- **Path ambiguity**: Does the agent have to discover the right menu/dialog, or is it told exactly which one?
- **Judgment required**: Does the agent need to evaluate options or make decisions, or just follow a recipe?
- **Subtask count**: How many independent goals must be achieved? Can they be done in any order?
- **Feature breadth**: Does the task require using multiple distinct features of the application?
- **Error tolerance**: Are there multiple ways to partially fail (wrong value, wrong target, partial completion)?

### Hard vs. Very Hard: description content

**Hard task description should include:**
- What the end state should look like
- Who/what the targets are (names, IDs)
- What values are expected
- NOT: which menu to use, which button to click, which dialog to navigate

**Very Hard task description should include:**
- The high-level goal only
- No target identification (agent must discover which records are wrong)
- No expected values (agent must determine correct values from context)
- No workflow hints (agent must explore the application to find the right feature)

### Design pattern: Contamination Injection for Very Hard tasks

One of the most effective mechanisms for a very hard task is **contamination injection**: `setup_task.sh` deliberately seeds a legitimate collection with a small number of "wrong" items, and the task description states only the high-level cleanup goal without naming the intruders. The agent must apply domain knowledge to classify each item and remove or reclassify the wrong ones.

**How it works**:
1. `setup_task.sh` injects N wrong items (known to you, the task creator) into an otherwise valid collection
2. The task description names the *domain constraint* ("this module should contain only amateur radio satellites") without identifying the specific intruders
3. The agent inspects the collection, applies domain knowledge, identifies the contaminating items by category/type/name
4. The verifier checks specifically for the removal/reclassification of each injected item

**Why this is genuinely hard**: The agent cannot brute-force this by randomly removing items. It must understand the domain well enough to distinguish legitimate from illegitimate items by their properties (satellite type, drug class, product category, species, etc.).

**Design constraints**:
- Inject items that are **plausibly similar in format** to legitimate ones — same data type, same field structure — but clearly wrong by domain knowledge. Items that look obviously fake are trivial; items that require real domain knowledge to distinguish are hard.
- Inject 3–6 items. Fewer than 3 is too easy to guess; more than 6 makes partial credit nearly impossible for agents with partial domain knowledge.
- The pass threshold should be **lower than the standard 70** (50–65 is appropriate), because discovery tasks penalize agents that have domain knowledge but missed one item. An agent that correctly identifies 3 of 4 injected items demonstrates meaningful reasoning even if it doesn't pass.
- **Document the injected items explicitly in task metadata** (`task.json`) so the verifier has ground truth without depending on the setup script.
- **Do not print ground truth in setup output.** `setup_task.sh` must not echo the specific items injected, their names, or their distinguishing properties in completion messages. While agents typically do not see pre_task hook output, some environments or debug configurations may expose it. Treat all setup output as potentially agent-visible and never include information the agent is supposed to discover.

**Common domains where this works well**: satellite category modules, pharmaceutical formularies, product/SKU catalogs by category, biological species by classification, financial instrument type registries, contact groups by organization.

### Design pattern: Error Injection into Config/World Files for Very Hard tasks

A companion to contamination injection. Instead of inserting wrong *items* into a collection, this pattern deliberately corrupts specific *field values* in an otherwise valid config, world, or parameter file. The agent must recognize that the system is broken, diagnose which fields are wrong, determine correct values from domain knowledge, and fix and save the file.

**How it differs from contamination injection**:
| | Contamination injection | Error injection |
|---|---|---|
| Unit of error | Item in a collection | Field value in a config |
| Agent's challenge | Classify items as valid/invalid | Diagnose broken values from failure signals |
| Verification | Check specific items removed/reclassified | Check fields are within valid ranges |
| Domain knowledge needed | Category/type classification | Correct physical/technical values |

**How it works**:
1. `setup_task.sh` starts from a valid, working file and programmatically corrupts 2–4 fields (using sed, Python regex, or similar)
2. The task description states only the high-level symptom ("the simulation is not behaving correctly — fix it") without identifying which fields are wrong or what the correct values are
3. The agent must inspect the file, recognize which values violate physical laws or domain conventions, and determine correct replacements
4. The verifier uses **range-based checks** (not exact equality) since the agent may choose any domain-valid correction

**Design constraints**:
- Use errors of different *types* — e.g., numeric out of physical range (gravity=0), structurally impossible value (mass=0), timing too slow (timestep=1024), reference to nonexistent entity. Errors of the same type are trivially diagnosed together.
- 2–4 errors is the right range. More than 4 makes diagnosis intractable without running the simulation interactively.
- The starting file must be valid and tested before `setup_task.sh` runs. Only the setup script introduces errors; the base file must be known-good.
- Document the exact injected errors in `task.json` metadata so the verifier has ground truth without reading the setup script at verification time.
- **Do not print injected errors or correct values in setup output.** Completion messages like `echo "Injected errors: field=wrong_value (should be correct_value)"` hand the agent the answer. Log only neutral messages (e.g., `echo "Setup complete"`) — never the specific fields, wrong values, or expected corrections.

**Example setup snippet** (Python inline in bash):
```bash
python3 << 'PYEOF'
import re
with open('/home/ga/projects/my_world.conf', 'r') as f:
    content = f.read()
content = re.sub(r'\btimestep\s+\d+', 'timestep 1024', content, count=1)  # Error 1: absurd timestep
content = re.sub(r'\bgravity\s+[\d.]+', 'gravity 0.0', content, count=1)  # Error 2: zero gravity
with open('/home/ga/projects/my_world.conf', 'w') as f:
    f.write(content)
PYEOF
```

**Common domains where this works well**: physics simulation (gravity, mass, friction, timestep), robotics (sensor ranges, joint limits, controller references), scientific computing (convergence tolerances, integration step size), audio/video processing (sample rate, bit depth, codec parameters).

---

### Range-Based Verification for Agent-Determined Values

For very_hard tasks using either error injection or open-ended repair, the verifier should accept any domain-valid correction — not just the single "canonical" value. This is distinct from Pattern 4 in `03_verification_patterns.md` (which rejects values outside realistic ranges). Here, the principle is: **"There are multiple correct answers; verify physical/domain validity, not a specific value."**

| Broken field | Agent might choose | Verifier checks |
|---|---|---|
| `timestep 1024` | 32, 16, 64, 8 | `timestep <= 64` |
| `gravity 0.0` | 9.81, 9.8, 9.807 | `abs(gravity) >= 9.0` |
| `mass 0.0` | 12.5, 10.0, 15.0 | `mass > 0.1` |
| `maxRange 5` | 100, 80, 120 | `maxRange >= 50` |

**When to use range-based checks**: Any very_hard task where the agent must determine correct values through domain reasoning rather than being told what the values should be.

**When to use exact checks**: Hard tasks where the description specifies exact expected values. If you told the agent "set gravity to 9.81," check for exactly 9.81 (or within floating-point tolerance).

### Design pattern: Parametric Sweep for Very Hard tasks

For **scriptable simulation or computation software** (energy modeling, FEA, CFD, statistical computing, etc.), a powerful very_hard pattern is to require the agent to run N ≥ 7 simulations across a swept parameter, aggregate the results, and identify an optimum. The task description gives the *goal* without telling the agent what to sweep, how many points to use, or which simulation module to invoke.

**How it works**:
1. Task description states a professional goal: "find the solar multiple that maximizes net present value" or "determine the hub height that minimizes LCOE."
2. The agent must: (a) identify the correct simulation model, (b) determine the appropriate parameter sweep range from domain knowledge, (c) run all N simulations programmatically, (d) aggregate results, and (e) identify the optimum.
3. The verifier checks: (a) that at least N sweep results are present in the output, (b) the reported optimum falls in the expected physical range, and (c) the output values obey physics/monotonicity constraints over the sweep.

**What makes this genuinely hard**:
- Requires programmatic control of the application (scripting, not just GUI interaction)
- Requires domain knowledge to choose sensible sweep bounds and step size
- Requires post-processing to identify the optimum from sweep results
- Running N=9 simulations manually through a GUI is impractical — forces scripted automation

**Design constraints**:
- N ≥ 7 sweep points. Fewer than 7 means the agent could plausibly guess the right answer without running the sweep.
- The optimal value must not be at the extreme of the sweep range (so the agent's range choice matters and trivial extrapolation is unrewarded).
- Use a parameter where the objective function is **non-monotonic** over the sweep (e.g., LCOE first decreases then increases with solar multiple due to capital cost vs. utilization tradeoff) — so the agent cannot infer the optimum without computing all points.
- The task description should imply the sweep dimension through professional context ("right-size the thermal storage for this location") without stating the exact parameter name or API key.

**Verification design**:
- Check that the reported optimum falls within a physically-valid range (not just "any number").
- Check that at least N sweep results are present in the output file — verifies the full sweep ran, not just a single simulation.
- Verify a monotonicity or trend constraint in a sub-range where physics dictates the direction (capacity factor must increase monotonically with solar multiple for a CSP system with TES).

**Applies to**: Any scriptable simulation software — energy system modeling (SAM, EnergyPlus), structural FEA (ANSYS, FEniCS), fluid dynamics (OpenFOAM), statistical/ML hyperparameter tuning (Python, R), financial scenario modeling, and traffic simulation (SUMO, VISSIM).

---

### Design pattern: Specification-Driven Discovery for Very Hard Tasks

For **any software where the task inherently requires knowing specific values** (dimensions, settings, parameters, policies), there is a natural tension: the agent must know the target values to complete the task, yet giving them in the description reduces difficulty to `hard` at best. The specification-driven discovery pattern resolves this.

**How it works**:
1. `setup_task.sh` drops a specification document at a predictable but not explicitly stated location — typically the desktop, a project folder, or a standard config directory within the VM.
2. The task description identifies the high-level goal ("the sketch needs dimensional constraints applied") but does NOT name the required values.
3. The agent must: (a) infer that a specification document likely exists, (b) locate it, (c) parse the relevant values from a realistic document, (d) apply those values in the application.
4. The verifier checks for the specific values from the spec — it knows them through `task.json` metadata, not from the description.

**What makes this genuinely hard**: The agent cannot complete the task by reading the description alone. It must exercise realistic professional judgment: "before configuring anything, I should find the specification." This mirrors how professionals actually work — a machinist reads the engineering drawing, a sysadmin reads the RFC, a developer reads the requirements doc.

**Document realism**: The spec file should look like an actual professional document, not a key=value dump. Include plausible context: a drawing number, issue date, author, notes. The required values should appear naturally within the document body, not formatted as a list of parameters to paste. An agent that only scans for numbers will miss context that determines which number means what.

**Verification design**:
- The spec values appear in `task.json` metadata (`required_constraints`, `expected_settings`, etc.) so the verifier has ground truth without reading the setup script at verification time.
- Use exact-value checks (within tolerance) since the spec specifies exact values and the agent is supposed to implement them precisely.
- If the spec contains more values than required (as real specs do), verify only the subset that the task specifically requires. Do not penalize the agent for applying additional correct values.

**What distinguishes this from error injection**: Error injection gives the agent a broken artifact to diagnose and fix — the agent must recognize what is wrong. Specification-driven discovery gives the agent a blank or partially-complete artifact to fill in per a spec — the agent must find and read the specification. Both are valid `very_hard` patterns; they test different reasoning skills (diagnostic vs. implementation).

**Applies to**: Any software where tasks require knowing specific numeric or categorical targets — CAD/drafting tools (dimensions), configuration management (parameter values), database administration (schema design), network configuration (IP ranges, VLANs), financial modeling (inputs), document formatting (styles), and software build configuration (flags and options).

---

### Handling Single-Primary-Workflow Environments

Some environments are built around one core operation — adding constraints (CAD tools), writing queries (databases), recording observations (clinical systems). When every task naturally uses that one operation, the feature matrix check will flag "feature appears in all 5 tasks."

**The important distinction**: Having the same *application feature* in all 5 tasks is less harmful than having the same *task archetype* in all 5 tasks.

For single-workflow environments, diversify by **archetype**, not by feature:

| Archetype | What the agent does |
|-----------|-------------------|
| Implement from spec | Reads an external spec, applies required values to a blank/partial artifact |
| Error repair | Identifies and corrects wrong values in an existing artifact |
| Multi-step pipeline | Chains 3+ operations in sequence (constrain → extrude → export) |
| Audit and annotate | Adds supplementary information (annotations, comments, metadata) to a real file |
| Batch with judgment | Applies the same operation to multiple targets, where the agent must decide which targets qualify |

If all 5 tasks use the same core feature (e.g., `PT_PT_DISTANCE` constraints) but each uses a different archetype from the table above, the task set is diverse in the ways that matter — the agent cannot learn one pattern and apply it mechanically to all 5. The feature matrix guideline should be applied at the archetype level when the application itself has a narrow feature set.

---

### Step Count Guidelines (UI clicks, not a difficulty measure)
- Easy: 5-10 steps
- Medium: 10-20 steps
- Hard: 20-35 steps
- Very Hard: 35-50+ steps

### Guidelines
- **Don't make tasks trivially easy**: Single-operation tasks don't test agent capabilities
- **Don't make tasks impossibly hard**: Agents need achievable goals for learning
- **Match task complexity to environment complexity**: Complex software warrants complex tasks
- **Include partial credit**: Multi-step tasks should reward progress
- **Do not confuse "clear goal" with "explicit instructions"**: A hard task has an unambiguous success criterion, but the agent must figure out how to achieve it

---

## Principle 6: Clear Task Description

**The agent must understand exactly WHAT the goal is — but for hard/very_hard tasks, must figure out HOW to achieve it.**

"Clear" means the success condition is unambiguous. It does NOT mean the UI path must be spelled out. Handing the agent step-by-step instructions is appropriate only for easy/medium tasks. For hard/very_hard tasks, providing explicit navigation steps reduces difficulty to near-zero.

### What to always include (all difficulty levels)
- **Login credentials**: The agent cannot guess these
- **Specific target**: Name the exact entity (patient name, document title, record ID) — for hard tasks
- **Expected end state**: What constitutes completion
- **Exact values to enter** (for hard tasks): What the correct value is, not which field to find it in

### What to omit for hard/very_hard tasks
- Which menu or toolbar item to use
- Which dialog will open and what options it has
- The sequence of clicks to reach any feature
- Which tab, panel, or section of the UI contains the relevant feature

---

## Principle 7: Documentation First

**Document everything before implementation.**

### Required Documentation
1. **README.md**: Full task description with domain context
2. **Ground truth data**: All database values and expected outcomes
3. **Verification strategy**: How each criterion will be checked
4. **Edge cases**: What could go wrong and how to handle it

### Benefits
- Forces clear thinking about requirements
- Enables review before implementation effort
- Creates reference for debugging issues
- Helps future task creators learn patterns

---

## Summary Checklist

Before implementing any task, verify:

- [ ] Task reflects real professional workflow
- [ ] Task passes the litmus test: a power user couldn't solve it in under 10 minutes by clicking around
- [ ] Uses REAL data from the environment or from real public datasets — absolutely NO synthetic/generated data
- [ ] Starting state is distinct from other tasks in this environment (different records/content)
- [ ] Has 3+ independent verification criteria
- [ ] Records baseline state to detect new work
- [ ] Rejects wrong-target actions with score=0
- [ ] Complexity matches difficulty rating
- [ ] For hard/very_hard: description does NOT spell out UI navigation steps
- [ ] Description is specific about the goal and end state
- [ ] README and metadata fully documented
