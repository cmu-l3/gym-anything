# Jamovi Environment — Evidence Documentation

## Summary

Jamovi 2.7.2 (latest stable) successfully installed and verified in a QEMU VM.
Five statistical analysis tasks confirmed working end-to-end via interactive VNC testing.

---

## Screenshot Index

### Initial-state screenshots (task start state, before any analysis)
| File | Task | Dataset | Description |
|------|------|---------|-------------|
| `init_task1_descriptive_statistics.png` | descriptive_statistics | Sleep.csv | Maximized window, 20 rows loaded, no analysis |
| `init_task2_independent_samples_ttest.png` | independent_samples_ttest | InvisibilityCloak.csv | Maximized window, 24 rows loaded, no analysis |
| `init_task3_one_way_anova.png` | one_way_anova | Viagra.csv | Maximized window, 30 rows loaded, no analysis |
| `init_task4_linear_regression.png` | linear_regression | ExamAnxiety.csv | Maximized window, 103 rows loaded, no analysis |
| `init_task5_reliability_analysis.png` | reliability_analysis | NeuroticiIndex.csv | Maximized window, 2694 rows (real bfi data), no analysis |

### Final-state screenshots (completed analysis, maximized window)
| File | Task | Key Results |
|------|------|-------------|
| `task1_descriptive_statistics_final.png` | descriptive_statistics | Split descriptives by group, histogram visible |
| `task2_independent_samples_ttest_final.png` | independent_samples_ttest | t=-1.71, p=.101, d=-0.700, descriptives |
| `task3_one_way_anova_final.png` | one_way_anova | F(2,27)=2.42, p=.108, Tukey post-hoc |
| `task4_linear_regression_final.png` | linear_regression | R²=0.209, β+CI for Revise+Anxiety |
| `task5_reliability_analysis_final.png` | reliability_analysis | α=0.813, ω=0.818, α-if-dropped per item |

---

## Installation Evidence

### pre_start log snippet
```
Installing runtime/org.freedesktop.Platform.GL.default/x86_64/24.08
Installing runtime/org.freedesktop.Platform/x86_64/24.08
Installing app/org.jamovi.jamovi/x86_64/stable
Jamovi flatpak installed successfully on attempt 1
Verifying Jamovi installation...
the jamovi team    org.jamovi.jamovi    2.7.2    stable
=== Downloading real research datasets ===
Sleep.csv downloaded: 178 bytes
Invisibility Cloak.csv downloaded: 185 bytes
Viagra.csv downloaded: 206 bytes
Exam Anxiety.csv downloaded: 2249 bytes
Created extract_bfi_neuroticism.py script (downloads Revelle 2010 bfi dataset)
All datasets downloaded and verified.
=== Jamovi installation complete ===
```

### Total env setup time
- `pre_start` hook: ~158 seconds (includes Flatpak install + dataset downloads)
- `pre_task` hook: ~28 seconds (Jamovi launch + data load)
- Total: ~186 seconds for a fresh install

---

## Dataset Evidence

All datasets confirmed present at `/home/ga/Documents/Jamovi/`:

```
-rw-r--r-- 1 ga ga   2249 ExamAnxiety.csv        (103 rows: Code,Revise,Exam,Anxiety,Gender)
-rw-r--r-- 1 ga ga    185 InvisibilityCloak.csv   (24 rows: Participant,Cloak,Mischief)
-rw-r--r-- 1 ga ga  26955 NeuroticiIndex.csv      (2694 rows: N1-N5, real bfi data, α=0.813)
-rw-r--r-- 1 ga ga    178 Sleep.csv               (20 rows: extra,group,ID)
-rw-r--r-- 1 ga ga    206 Viagra.csv              (30 rows: dose,libido,partnerLibido)
```

Datasets 1-4 sourced from: https://github.com/jasp-stats/jasp-desktop/tree/master/Resources/Data%20Sets/
NeuroticiIndex.csv: **Real** Big Five Inventory Neuroticism items (Revelle, 2010, psych R package bfi dataset).
  2,694 complete participants, N1-N5 items on 1–6 Likert scale, Cronbach's α=0.813, McDonald's ω=0.818.
  Extracted from: https://raw.githubusercontent.com/vincentarelbundock/Rdatasets/master/csv/psych/bfi.csv

---

## Interactive Task Testing Evidence

### Task 1: descriptive_statistics
**Initial state**: `init_task1_descriptive_statistics.png` — Sleep.csv loaded, 20 rows, no analysis
**Final state**: `task1_descriptive_statistics_final.png` — maximized, full analysis visible

**Sleep.csv** (20 rows: extra, group, ID)
- ✅ Exploration → Descriptives panel opened
- ✅ 'extra' moved to Variables box
- ✅ 'group' moved to Split by box
- ✅ Statistics expanded: Mean, Median, SD, Min, Max checked
- ✅ Plots expanded: Histogram enabled
- **Results**: Split statistics for group 1 (n=10, M=0.75) and group 2 (n=10, M=2.33) with histograms

### Task 2: independent_samples_t_test
**Initial state**: `init_task2_independent_samples_ttest.png` — InvisibilityCloak.csv loaded, 24 rows, no analysis
**Final state**: `task2_independent_samples_ttest_final.png` — maximized, full analysis visible

**InvisibilityCloak.csv** (24 rows: Participant, Mischief, Cloak)
- ✅ T-Tests → Independent Samples T-Test panel opened
- ✅ 'Mischief' moved to Dependent Variables box
- ✅ 'Cloak' moved to Grouping Variable box
- ✅ Effect size (Cohen's d) enabled
- ✅ Descriptives table enabled
- **Results**: t=-1.713, df=22, p=.101, Cohen's d=-0.700 (non-significant trend)

### Task 3: one_way_anova
**Initial state**: `init_task3_one_way_anova.png` — Viagra.csv loaded, 30 rows, no analysis
**Final state**: `task3_one_way_anova_final.png` — maximized, full analysis visible

**Viagra.csv** (30 rows: dose [1=Placebo/2=Low/3=High], libido, partnerLibido)
- ✅ ANOVA → One-Way ANOVA panel opened
- ✅ 'libido' moved to Dependent Variable box
- ✅ 'dose' moved to Grouping Variable box
- ✅ Variances: Assume equal (Fisher's) selected
- ✅ Post Hoc Tests: Tukey (equal variances) selected
- ✅ Additional Statistics: Descriptives table enabled
- **Results**: F(2,27)=2.42, p=.108; Tukey post-hoc pairwise comparisons shown; Group Descriptives table with N, M, SD, SE

### Task 4: linear_regression
**Initial state**: `init_task4_linear_regression.png` — ExamAnxiety.csv loaded, 103 rows, no analysis
**Final state**: `task4_linear_regression_final.png` — maximized, full analysis visible

**ExamAnxiety.csv** (103 rows: Code, Revise, Exam, Anxiety, Gender)
- ✅ Regression → Linear Regression panel opened
- ✅ 'Exam' moved to Dependent Variable box
- ✅ 'Revise' and 'Anxiety' moved to Covariates box
- ✅ Model Fit: R, R², F test enabled
- ✅ Model Coefficients: Standardized estimate (β) enabled
- ✅ Model Coefficients: Confidence interval enabled
- **Results**: R²=0.209, F(2,100)=13.2 p<.001; Anxiety β=-0.321 (p=.012), Revise β=0.169 (p=.184); 95% CIs shown

### Task 5: reliability_analysis
**Initial state**: `init_task5_reliability_analysis.png` — NeuroticiIndex.csv loaded, 2694 rows (real bfi data), no analysis
**Final state**: `task5_reliability_analysis_final.png` — maximized, full analysis visible

**NeuroticiIndex.csv** (2,694 rows: N1-N5 from Revelle 2010 bfi dataset, 1-6 Likert scale)
- ✅ Factor → Reliability Analysis panel opened
- ✅ All 5 items (N1-N5) moved to Items box
- ✅ Scale Statistics: Cronbach's α (default) + McDonald's ω enabled
- ✅ Item Statistics: Cronbach's α (if item dropped) enabled
- **Results**: α=0.813, ω=0.818; α-if-dropped: N1=0.757, N2=0.763, N3=0.755, N4=0.795, N5=0.812

---

## Critical Notes for Future Reference

1. **D-Bus session bus required**: Jamovi uses `zypak` (Flatpak Electron sandbox) which requires a D-Bus session bus. When launching from root hook scripts via `su - ga -c`, the D-Bus session bus address must be set explicitly. The launcher script (`/usr/local/bin/launch-jamovi`) sets: `DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus`.

2. **--no-sandbox flag required**: Chromium/Electron sandbox fails in QEMU VMs. Pass `-- --no-sandbox --disable-gpu` as Flatpak app arguments.

3. **Window title is filename**: Jamovi sets window title to the dataset filename (e.g., "Sleep" for Sleep.csv), not "jamovi". Use `wmctrl -r ":ACTIVE:"` to maximize.

4. **Flatpak install succeeds on first attempt**: Unlike JASP, Jamovi's Flatpak installed successfully on attempt 1 (runtimes were already cached from JASP install).

5. **Process detection**: Use `pgrep -f "jamovi.server"` to check if Jamovi is running.

6. **One-Way ANOVA has no Effect size (η²) option**: Jamovi's "One-Way ANOVA" module only has Descriptives table and Descriptives plots under Additional Statistics. Effect size (η²) is only available in the full "ANOVA" module. Task 3 uses Tukey + Descriptives table only.

7. **Reliability analysis requires item-level data**: Cronbach's α requires individual item responses, not composite scores. The NeuroticiIndex.csv uses **real** bfi data (Revelle 2010, psych R package) extracted via `extract_bfi_neuroticism.py`. The original BigFivePersonalityTraits.csv from JASP GitHub has composite scale scores only — unsuitable for reliability analysis.
