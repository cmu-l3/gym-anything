# JASP Environment — Evidence Documentation

## Environment: `jasp_env@0.1`

**Date tested:** 2026-02-19
**JASP version:** 0.95.4 (Flatpak, Flathub)
**Base image:** ubuntu-gnome-systemd_highres
**Fresh reset time:** ~249s | Cached reset time: ~71s

---

## Verification Checklist

### ✅ Installation (pre_start hook)
- [x] Flatpak and dependencies installed
- [x] JASP 0.95.4 installed via Flatpak (retry loop handles first-attempt 404)
- [x] All 5 real research datasets downloaded and verified

### ✅ Setup (post_start hook)
- [x] Datasets copied to `/home/ga/Documents/JASP/` with space-free names
- [x] `/usr/local/bin/launch-jasp` wrapper created (sets `QTWEBENGINE_CHROMIUM_FLAGS=--no-sandbox`)
- [x] JASP config pre-created to suppress update dialogs
- [x] Warm-up launch performed (JASP settles first-run state, then killed)

### ✅ Task Start States (pre_task hook)
All 5 tasks: JASP opens cleanly with correct dataset, no startup dialogs.

| Task | Dataset Loaded | Start State Screenshot |
|------|---------------|------------------------|
| `descriptive_statistics` | Sleep.csv (extra, group, ID) | task_descriptive_statistics.png |
| `independent_samples_t_test` | InvisibilityCloak.csv (Participant, Cloak, Mischief) | task_independent_samples_t_test.png |
| `one_way_anova` | Viagra.csv (dose, libido, partnerLibido) | task_one_way_anova.png |
| `linear_regression` | ExamAnxiety.csv (Code, Revise, Exam, Anxiety, Gender) | task_linear_regression.png |
| `correlation_matrix` | BigFivePersonalityTraits.csv (5 trait columns) | task_correlation_matrix.png |

### ✅ Task Completability Evidence
Interactive testing confirmed all tasks are completable end-to-end:

| Task | Evidence | Completion Screenshot |
|------|---------|----------------------|
| `descriptive_statistics` | Descriptives tab opened; extra→Variables, group→Split; Statistics enabled (Mean/SD/Min/Max/Median); Group 1 (n=10, mean=0.75) and Group 2 (n=10, mean=2.33) | task_descriptive_statistics_completion.png |
| `independent_samples_t_test` | T-Tests panel opened; Mischief→Dependent Variables, Cloak→Grouping Variable; t=-1.713, df=22, p=.101; **Descriptives table** shows Group 0 (N=12, Mean=3.750) and Group 1 (N=12, Mean=5.000) | task_independent_samples_t_test_completion.png |
| `one_way_anova` | ANOVA panel opened; libido→Dependent Variable, dose→Fixed Factors; F(2,27)=2.416, p=.108; **η²=0.152 column** visible in ANOVA table; **Descriptives table** shows dose groups with means | task_one_way_anova_completion.png |
| `linear_regression` | Regression panel opened; Exam→Dependent Variable, Revise+Anxiety→Covariates; R²=0.209, F=13.16, p<.001; **Descriptives table** shows Exam (Mean=56.57), Revise (Mean=19.65), Anxiety (Mean=74.34) | task_linear_regression_completion.png |
| `correlation_matrix` | Correlation panel opened (Regression→Correlation); all 5 traits→Variables; Pearson matrix with significant correlations flagged (***); **Heatmap plot** visible below table; Neuroticism↔Conscientiousness r=-0.368*** p<.001 | task_correlation_matrix_completion.png |

---

## Setup Log Snippets

### pre_start (install) log — tail
```
Installing runtime/org.kde.Platform/x86_64/6.9
Installing app/org.jaspstats.JASP/x86_64/stable
Error: Failed to install org.jaspstats.JASP: While pulling app/org.jaspstats.JASP/x86_64/stable from remote flathub: Server returned status 404: Not Found
Attempt 1 failed, retrying in 10s...
Attempt 2: flatpak install JASP...
Installing app/org.jaspstats.JASP/x86_64/stable
JASP flatpak installed successfully on attempt 2
Verifying JASP installation...
University of Amsterdam	org.jaspstats.JASP	0.95.4	stable
=== Downloading real JASP example datasets from official JASP GitHub ===
Sleep.csv downloaded: 178 bytes
Invisibility Cloak.csv downloaded: 185 bytes
Viagra.csv downloaded: 206 bytes
Exam Anxiety.csv downloaded: 2249 bytes
Big Five Personality Traits.csv downloaded: 18494 bytes
All datasets downloaded and verified.
=== JASP installation complete ===
```

### post_start (setup) log
```
=== Setting up JASP environment ===
Confirmed: Sleep.csv is 178 bytes
Confirmed: Invisibility Cloak.csv is 185 bytes
Confirmed: Viagra.csv is 206 bytes
Confirmed: Exam Anxiety.csv is 2249 bytes
Confirmed: Big Five Personality Traits.csv is 18494 bytes
Datasets copied to /home/ga/Documents/JASP/ (with space-free names)
Created /usr/local/bin/launch-jasp
JASP config pre-created at /home/ga/.var/app/org.jaspstats.JASP/config/JASP/JASP.conf
Performing warm-up launch of JASP...
JASP warm-up complete.
JASP is installed via flatpak (system-wide)
=== JASP setup complete ===
```

### Datasets in `/home/ga/Documents/JASP/`
```
-rw-r--r-- 1 ga ga 18494 BigFivePersonalityTraits.csv
-rw-r--r-- 1 ga ga  2249 ExamAnxiety.csv
-rw-r--r-- 1 ga ga   185 InvisibilityCloak.csv
-rw-r--r-- 1 ga ga   178 Sleep.csv
-rw-r--r-- 1 ga ga   206 Viagra.csv
```

### JASP Flatpak Version
```
University of Amsterdam    org.jaspstats.JASP    0.95.4    stable    system
```

---

## Dataset Sources

All datasets are **real research data** from published papers, sourced from the official JASP GitHub repository (`jasp-stats/jasp-desktop`):

| File | Source Paper | Size |
|------|-------------|------|
| Sleep.csv | Student/Gosset (1908) sleep study | 178 B |
| InvisibilityCloak.csv | Field (2013) field experiment | 185 B |
| Viagra.csv | Pharmacological study on libido | 206 B |
| ExamAnxiety.csv | Field (2013) academic performance study | 2.2 KB |
| BigFivePersonalityTraits.csv | NEO personality inventory (231 participants) | 18 KB |

---

## Key Technical Notes

1. **QTWEBENGINE_CHROMIUM_FLAGS="--no-sandbox"** — Required in QEMU; without it JASP crashes with SIGTRAP
2. **Flatpak retry loop** — First install attempt gets 404; runtimes cache on attempt 1, app succeeds on attempt 2
3. **Space-free filenames** — "Invisibility Cloak.csv" → "InvisibilityCloak.csv" etc., because spaces cause arg splitting through `su→setsid→flatpak` chain
4. **setsid required** — `su - ga -c "setsid /usr/local/bin/launch-jasp ..."` prevents SIGHUP from killing JASP when `su` exits
