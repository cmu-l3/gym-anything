# wger_env Evidence Documentation

## Environment Overview

**Application**: wger Workout Manager (https://wger.de)
**Version**: wger/server:latest (2.5-dev)
**Stack**: Docker Compose — wger-web (gunicorn), wger-nginx, wger-db (PostgreSQL 15), wger-cache (Redis)
**URL**: http://localhost
**Admin credentials**: admin / adminadmin

## Interactive Testing Results

### Environment Startup
- `pre_start` (install_wger.sh): ~90s — installs Docker CE, docker-compose-plugin, Firefox snap, xdotool, wmctrl
- `post_start` (setup_wger.sh): ~418s — pulls Docker images, DB migrations, exercise sync, seed data, Firefox launch

### Container Health (tested 2026-02-22)
```
wger-nginx   Up (running)  0.0.0.0:80->80/tcp
wger-web     Up (healthy)  8000/tcp (via gunicorn)
wger-db      Up (healthy)  5432/tcp (PostgreSQL 15)
wger-cache   Up (healthy)  6379/tcp (Redis)
```

### API Health Check
- `GET http://localhost/api/v2/` → HTTP 200 ✓
- JWT token endpoint: `POST /api/v2/token` → 231-char access token ✓

### Database Content After post_start
```
Users: 1 (admin)
Routines for admin: 6 (Push-Pull-Legs, 5x5 Beginner, Upper-Lower Split + task-created)
Weight entries for admin: 30 (30-day history, 87kg → 82.65kg declining)
Nutrition plans for admin: 3 (Maintenance Diet, Lean Bulk Plan + task-created)
Measurement categories for admin: 3 (Body Fat/%, Chest/cm, Waist/cm, each with 5 entries)
Total exercises in DB: 414 (synced from wger.de via sync-exercises management command)
```

## Task Start States (all 10 tasks verified via visual_grounding — 2026-02-22)

| Task | Pre-task Setup | Start URL | Verified |
|------|---------------|-----------|--------|
| create_workout_routine | Navigate to /en/routine/overview | /en/routine/overview | ✓ 3 seed routines shown |
| add_training_day | Create Power Training routine → navigate to view page | /en/routine/{id}/view | ✓ Power Training routine page |
| log_workout_session | Delete existing WorkoutSessions → Create Full Body Workout routine → navigate to calendar | /en/routine/calendar | ✓ February 2026 calendar; dots on Feb 14-20 are weight entry markers (seed data), NOT stale sessions; today (Feb 22) has no dot |
| log_body_weight | Navigate to /en/weight/overview/ | /en/weight/overview/ | ✓ Chart + table with 30-day history |
| change_weight_unit | Reset weight unit to kg → navigate to preferences | /en/user/preferences | ✓ Preferences page (scroll down for Weight unit dropdown) |
| add_measurement_category | Navigate to /en/measurement/ | /en/measurement/ | ✓ Waist and Chest categories with data charts visible |
| create_nutrition_plan | Navigate to /en/nutrition/overview/ | /en/nutrition/overview/ | ✓ 2 seed plans shown |
| set_nutrition_goal | Create Athlete Diet plan → navigate to view | /en/nutrition/{id}/view/ | ✓ Athlete Diet plan with 0 goals |
| register_new_user | Clean up john_trainee → navigate to gym add-member | /en/gym/1/add-member | ✓ Add user to gym form |
| add_meal_to_plan | Create Muscle Building plan → navigate to view | /en/nutrition/{id}/view/ | ✓ Muscle Building plan |

## Screenshots

### Baseline screenshots (recaptured 2026-02-22 — working app state)
- `01_login_page.png` — wger login page at /en/user/login (username + password fields visible)
- `02_dashboard.png` — wger dashboard (logged in as admin; 5 widgets: Routine, Nutrition, Weight, Calendar, Measurements)
- `03_routine_overview.png` — Routines list at /en/routine/overview (5 routines visible with + FAB)
- `04_nutrition_overview.png` — Nutrition plans at /en/nutrition/overview/ (4 plans visible)
- `05_weight_overview.png` — Body weight history at /en/weight/overview (30-day chart + data table)
- `06_measurement.png` — Measurements page at /en/measurement/ (Waist + Chest charts with data)

### Task start states (captured 2026-02-22 via visual_grounding)
- `task01_create_workout_routine.png` — Routines overview with 3 seed routines
- `task02_add_training_day.png` — Power Training routine view page
- `task03_log_workout_session.png` — Workout calendar (Feb 2026); dots on Feb 14-20 are weight entry markers from seed data; today Feb 22 is highlighted red with empty Entries panel (clean state)
- `task04_log_body_weight.png` — Weight overview with chart and 30-day data table
- `task05_change_weight_unit.png` — User preferences page scrolled to show Weight unit dropdown (currently: Metric/kilogram)
- `task06_add_measurement_category.png` — Measurements page with Waist + Chest categories showing data charts
- `task07_create_nutrition_plan.png` — Nutrition overview with 2 seed plans
- `task08_set_nutrition_goal.png` — Athlete Diet nutrition plan (all goals = 0)
- `task09_register_new_user.png` — Add user to gym form at /en/gym/1/add-member
- `task10_add_meal_to_plan.png` — Muscle Building nutrition plan (empty, ready for meals)

## Key Bugs Fixed

1. **Redis cache incompatibility**: Changed `DJANGO_CACHE_BACKEND` to `django_redis.cache.RedisCache` + added `DJANGO_CACHE_CLIENT_CLASS=django_redis.client.DefaultClient` to avoid TypeError from redis-py 6.4.0
2. **Missing USE_CELERY=False**: Added to prod.env (no celery containers in compose)
3. **Routine requires start/end**: Wger's Routine model has required DateFields `start` and `end`; all task setup scripts and seed data fixed
4. **Wrong module wger.training.models**: Correct module is `wger.manager.models` for Routine, Day, WorkoutSession
5. **Wrong class MeasurementCategory**: Correct class is `Category` from `wger.measurements.models`
6. **Wrong module wger.workoutsession**: WorkoutSession lives in `wger.manager.models`, not a separate module
7. **Wrong field workout**: WorkoutSession.workout → WorkoutSession.routine (FK to Routine)
8. **JWT token trailing slash**: `/api/v2/token/` returns 404; correct is `/api/v2/token`
9. **xwd pipe in SSH**: `xwd | convert` pipe breaks in SSH context; fixed to use temp file: `xwd -out /tmp/raw.xwd && convert /tmp/raw.xwd output.png`
10. **Snap Firefox permission**: `chown -R ga:ga "${FIREFOX_PROFILE_BASE}"` didn't fix snap version dirs; fixed to `chown -R ga:ga /home/ga/snap/` — and lock removal must be inside `su - ga -c` block
11. **React SPA blank content**: collectstatic not run on startup because entrypoint only runs it when `DJANGO_DEBUG=False`; fixed by adding `DJANGO_DEBUG=False` to prod.env AND adding explicit collectstatic call in setup_wger.sh
12. **Wrong URL change_weight_unit**: `/en/user/1/config` → 404; correct URL is `/en/user/preferences` (has Weight unit dropdown)
13. **Wrong URL register_new_user**: `/en/user/add` and `/en/user/registration` both 404 (or redirect to dashboard); correct URL is `/en/gym/1/add-member` (gym admin add-member form)
14. **Blank measurement charts**: Seed measurement entries missing from savevm (one-time silent failure in seed script); fixed by adding explicit idempotent measurement seeding step (step 7b) in setup_wger.sh
15. **Calendar dots misidentified**: Calendar dots on Feb 14-20 are from WeightEntry seed data (not stale WorkoutSession objects); WorkoutSession deletion added to log_workout_session setup_task.sh as defensive measure

## Files Modified (complete list — 2026-02-22)
- `config/prod.env` — Fixed Redis cache backend; added USE_CELERY=False; added DJANGO_DEBUG=False (critical for collectstatic)
- `env.json` — Added standard gym_anything fields (diagnostics, action, vnc, recording, etc.)
- `scripts/install_wger.sh` — Installs Docker CE, docker-compose-plugin, Firefox snap, xdotool, wmctrl
- `scripts/setup_wger.sh` — Seed data via file-based docker exec (not heredoc); snap chown fix; explicit collectstatic step
- `scripts/task_utils.sh` — Added `launch_firefox_to()` for cold Firefox start; fixed JWT token URL; fixed take_screenshot() temp file; fixed `$(seq)` loop bug
- `tasks/*/verifier.py` (all 10) — Converted to stubs (VLM verification is external)
- `tasks/*/setup_task.sh` (all 10) — Updated to use `launch_firefox_to()` instead of `navigate_to()`
- `tasks/change_weight_unit/setup_task.sh` — Fixed URL: /en/user/1/config → /en/user/preferences
- `tasks/register_new_user/setup_task.sh` — Fixed URL: /en/user/add → /en/gym/1/add-member
- `tasks/register_new_user/task.json` — Removed password fields (gym add-member form has no password field)
- `evidence/README.md` — Updated with interactive testing results and new task screenshots
- `evidence/task01-10_*.png` — Task start state screenshots (captured 2026-02-22)
