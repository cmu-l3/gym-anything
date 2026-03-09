#!/usr/bin/env python3
"""
Offline verifier unit tests for all 5 new wger_env tasks.
Uses mock copy_from_env to test do-nothing, partial, and full scenarios
without requiring a live VM.

Usage: python3 benchmarks/environments/wger_env/evidence/test_verifiers_offline.py
"""

import importlib.util
import json
import os
import sys

TASKS_DIR = os.path.join(os.path.dirname(__file__), '..', 'tasks')


def load_verifier(task_name):
    path = os.path.join(TASKS_DIR, task_name, 'verifier.py')
    spec = importlib.util.spec_from_file_location('verifier', path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def make_env(result_data):
    def copy_from_env(src, dst):
        with open(dst, 'w') as f:
            json.dump(result_data, f)
    return {'copy_from_env': copy_from_env}


def make_env_missing():
    def copy_from_env(src, dst):
        raise FileNotFoundError(f"No such file: {src}")
    return {'copy_from_env': copy_from_env}


def run_test(name, fn, env_info, task_info, expect_passed, score_min, score_max):
    r = fn([], env_info, task_info)
    passed_ok = r['passed'] == expect_passed
    score_ok = score_min <= r['score'] <= score_max
    status = "PASS" if (passed_ok and score_ok) else "FAIL"
    print(f"  [{status}] {name}: passed={r['passed']} score={r['score']} "
          f"(expect passed={expect_passed}, score {score_min}-{score_max})")
    if not (passed_ok and score_ok):
        print(f"         feedback: {r.get('feedback', '')[:200]}")
    return passed_ok and score_ok


# ===========================================================================
# Task 1: endurance_athlete_periodization
# ===========================================================================
def test_endurance_athlete_periodization():
    print("\n=== endurance_athlete_periodization ===")
    mod = load_verifier('endurance_athlete_periodization')
    fn = mod.verify_endurance_athlete_periodization
    task_info = {}
    all_pass = True

    # Do-nothing: result file missing
    r = run_test("do-nothing (file missing)", fn, make_env_missing(), task_info,
                 expect_passed=False, score_min=0, score_max=0)
    all_pass = all_pass and r

    # Do-nothing: nothing created
    empty_result = {
        'weight_entries': {
            d: {'exists': False, 'weight_kg': None}
            for d in ['2026-01-06','2026-01-13','2026-01-20','2026-01-27',
                      '2026-02-03','2026-02-10','2026-02-17','2026-02-24']
        },
        'measurement_data': {
            'Cooper Test Distance': {'exists': False, 'unit': None, 'entries': {}},
            'Resting Heart Rate': {'exists': False, 'unit': None, 'entries': {}},
        },
        'routine': {'found': False, 'description': None, 'days': []},
        'nutrition_plan': {'found': False},
    }
    r = run_test("do-nothing (empty result)", fn, make_env(empty_result), task_info,
                 expect_passed=False, score_min=0, score_max=0)
    all_pass = all_pass and r

    # Partial: only weight entries correct + nutrition plan exists (no macros)
    partial_result = {
        'weight_entries': {
            '2026-01-06': {'exists': True, 'weight_kg': 68.2},
            '2026-01-13': {'exists': True, 'weight_kg': 67.9},
            '2026-01-20': {'exists': True, 'weight_kg': 67.5},
            '2026-01-27': {'exists': True, 'weight_kg': 67.8},
            '2026-02-03': {'exists': True, 'weight_kg': 67.4},
            '2026-02-10': {'exists': True, 'weight_kg': 67.1},
            '2026-02-17': {'exists': True, 'weight_kg': 66.8},
            '2026-02-24': {'exists': True, 'weight_kg': 66.5},
        },
        'measurement_data': {
            'Cooper Test Distance': {'exists': False, 'unit': None, 'entries': {}},
            'Resting Heart Rate': {'exists': False, 'unit': None, 'entries': {}},
        },
        'routine': {'found': False, 'description': None, 'days': []},
        'nutrition_plan': {'found': True, 'goal_energy': 0, 'goal_protein': 0,
                           'goal_carbohydrates': 0, 'goal_fat': 0},
    }
    r = run_test("partial (weights + plan, no categories/routine/macros)", fn,
                 make_env(partial_result), task_info,
                 expect_passed=False, score_min=20, score_max=59)
    all_pass = all_pass and r

    # Full: everything correct
    full_result = {
        'weight_entries': {
            '2026-01-06': {'exists': True, 'weight_kg': 68.2},
            '2026-01-13': {'exists': True, 'weight_kg': 67.9},
            '2026-01-20': {'exists': True, 'weight_kg': 67.5},
            '2026-01-27': {'exists': True, 'weight_kg': 67.8},
            '2026-02-03': {'exists': True, 'weight_kg': 67.4},
            '2026-02-10': {'exists': True, 'weight_kg': 67.1},
            '2026-02-17': {'exists': True, 'weight_kg': 66.8},
            '2026-02-24': {'exists': True, 'weight_kg': 66.5},
        },
        'measurement_data': {
            'Cooper Test Distance': {
                'exists': True, 'unit': 'm',
                'entries': {'2026-01-10': 3420, '2026-01-24': 3465,
                            '2026-02-07': 3510, '2026-02-21': 3555}
            },
            'Resting Heart Rate': {
                'exists': True, 'unit': 'bpm',
                'entries': {'2026-01-10': 52, '2026-01-24': 51,
                            '2026-02-07': 50, '2026-02-21': 49}
            },
        },
        'routine': {
            'found': True,
            'description': 'Elite marathon runner spring race preparation: Base, Build, Peak, Taper phases',
            'days': [
                {'name': 'Base Phase - Long Run', 'day_of_week': [7], 'exercises': ['Running']},
                {'name': 'Base Phase - Easy Recovery', 'day_of_week': [3], 'exercises': ['Walking']},
                {'name': 'Build Phase - Tempo Work', 'day_of_week': [2], 'exercises': ['Running', 'Cycling']},
                {'name': 'Build Phase - Long Intervals', 'day_of_week': [5], 'exercises': ['Running']},
                {'name': 'Peak Phase - Race Pace', 'day_of_week': [2], 'exercises': ['Running']},
                {'name': 'Taper Phase - Shakeout', 'day_of_week': [5], 'exercises': ['Running', 'Walking']},
            ]
        },
        'nutrition_plan': {
            'found': True,
            'goal_energy': 3200.0,
            'goal_protein': 145.0,
            'goal_carbohydrates': 480.0,
            'goal_fat': 75.0,
        },
    }
    r = run_test("full completion", fn, make_env(full_result), task_info,
                 expect_passed=True, score_min=60, score_max=100)
    all_pass = all_pass and r

    return all_pass


# ===========================================================================
# Task 2: rehab_exercise_protocol
# ===========================================================================
def test_rehab_exercise_protocol():
    print("\n=== rehab_exercise_protocol ===")
    mod = load_verifier('rehab_exercise_protocol')
    fn = mod.verify_rehab_exercise_protocol
    task_info = {}
    all_pass = True

    # Do-nothing
    empty_result = {
        'weight_entries': {d: {'exists': False, 'weight_kg': None}
                           for d in ['2026-01-12','2026-01-19','2026-01-26',
                                     '2026-02-02','2026-02-09','2026-02-16']},
        'measurement_data': {
            '6-Minute Walk Distance': {'exists': False, 'unit': None, 'entries': {}},
            'Resting Systolic BP': {'exists': False, 'unit': None, 'entries': {}},
            'Borg RPE Score': {'exists': False, 'unit': None, 'entries': {}},
        },
        'routine': {'found': False, 'description': None, 'days': []},
        'nutrition_plan': {'found': False},
    }
    r = run_test("do-nothing (empty result)", fn, make_env(empty_result), task_info,
                 expect_passed=False, score_min=0, score_max=0)
    all_pass = all_pass and r

    # Partial: only 3 weight entries + routine (no measurements or plan)
    partial_result = {
        'weight_entries': {
            '2026-01-12': {'exists': True, 'weight_kg': 88.5},
            '2026-01-19': {'exists': True, 'weight_kg': 87.8},
            '2026-01-26': {'exists': True, 'weight_kg': 87.2},
            '2026-02-02': {'exists': False, 'weight_kg': None},
            '2026-02-09': {'exists': False, 'weight_kg': None},
            '2026-02-16': {'exists': False, 'weight_kg': None},
        },
        'measurement_data': {
            '6-Minute Walk Distance': {'exists': False, 'unit': None, 'entries': {}},
            'Resting Systolic BP': {'exists': False, 'unit': None, 'entries': {}},
            'Borg RPE Score': {'exists': False, 'unit': None, 'entries': {}},
        },
        'routine': {
            'found': True,
            'description': 'Supervised outpatient cardiac rehab: 12-week progressive aerobic and resistance program',
            'days': [
                {'name': 'Aerobic Warm-Up and Walking', 'day_of_week': [1], 'exercises': ['Walking']},
            ]
        },
        'nutrition_plan': {'found': False},
    }
    r = run_test("partial (3 weights + routine with 1 day)", fn,
                 make_env(partial_result), task_info,
                 expect_passed=False, score_min=10, score_max=57)
    all_pass = all_pass and r

    # Full completion
    full_result = {
        'weight_entries': {
            '2026-01-12': {'exists': True, 'weight_kg': 88.5},
            '2026-01-19': {'exists': True, 'weight_kg': 87.8},
            '2026-01-26': {'exists': True, 'weight_kg': 87.2},
            '2026-02-02': {'exists': True, 'weight_kg': 86.9},
            '2026-02-09': {'exists': True, 'weight_kg': 86.4},
            '2026-02-16': {'exists': True, 'weight_kg': 85.8},
        },
        'measurement_data': {
            '6-Minute Walk Distance': {
                'exists': True, 'unit': 'm',
                'entries': {'2026-01-14': 310, '2026-01-28': 342,
                            '2026-02-11': 378, '2026-02-25': 415, '2026-03-04': 448}
            },
            'Resting Systolic BP': {
                'exists': True, 'unit': 'mmHg',
                'entries': {'2026-01-14': 148, '2026-01-28': 143,
                            '2026-02-11': 138, '2026-02-25': 134, '2026-03-04': 130}
            },
            'Borg RPE Score': {
                'exists': True, 'unit': 'RPE',
                'entries': {'2026-01-14': 14, '2026-01-28': 13,
                            '2026-02-11': 12, '2026-02-25': 12, '2026-03-04': 11}
            },
        },
        'routine': {
            'found': True,
            'description': 'Supervised outpatient cardiac rehab: 12-week progressive aerobic and resistance program',
            'days': [
                {'name': 'Aerobic Warm-Up and Walking', 'day_of_week': [1], 'exercises': ['Walking']},
                {'name': 'Low-Intensity Resistance Circuit', 'day_of_week': [3],
                 'exercises': ['Dumbbell Lateral Raise', 'Bicep Curl']},
                {'name': 'Active Recovery and Flexibility', 'day_of_week': [5], 'exercises': ['Walking']},
            ]
        },
        'nutrition_plan': {
            'found': True,
            'goal_energy': 2100.0,
            'goal_protein': 95.0,
            'goal_carbohydrates': 280.0,
            'goal_fat': 58.0,
        },
    }
    r = run_test("full completion", fn, make_env(full_result), task_info,
                 expect_passed=True, score_min=58, score_max=100)
    all_pass = all_pass and r

    return all_pass


# ===========================================================================
# Task 3: sports_nutrition_consultation
# ===========================================================================
def test_sports_nutrition_consultation():
    print("\n=== sports_nutrition_consultation ===")
    mod = load_verifier('sports_nutrition_consultation')
    fn = mod.verify_sports_nutrition_consultation
    task_info = {}
    all_pass = True

    # Do-nothing
    empty_result = {
        'weight_entries': {d: {'exists': False, 'weight_kg': None}
                           for d in ['2026-01-05','2026-01-12','2026-01-19','2026-01-26',
                                     '2026-02-02','2026-02-09','2026-02-16','2026-02-23']},
        'measurement_data': {
            'Body Fat Percentage': {'exists': False, 'unit': None, 'entries': {}},
            'Lean Body Mass': {'exists': False, 'unit': None, 'entries': {}},
            'Vertical Jump Height': {'exists': False, 'unit': None, 'entries': {}},
        },
        'offseason_plan': {'found': False},
        'competition_plan': {'found': False},
    }
    r = run_test("do-nothing (empty result)", fn, make_env(empty_result), task_info,
                 expect_passed=False, score_min=0, score_max=0)
    all_pass = all_pass and r

    # Partial: off-season plan exists with correct macros but no meals, no measurements
    partial_result = {
        'weight_entries': {d: {'exists': False, 'weight_kg': None}
                           for d in ['2026-01-05','2026-01-12','2026-01-19','2026-01-26',
                                     '2026-02-02','2026-02-09','2026-02-16','2026-02-23']},
        'measurement_data': {
            'Body Fat Percentage': {'exists': False, 'unit': None, 'entries': {}},
            'Lean Body Mass': {'exists': False, 'unit': None, 'entries': {}},
            'Vertical Jump Height': {'exists': False, 'unit': None, 'entries': {}},
        },
        'offseason_plan': {
            'found': True,
            'goal_energy': 4200.0, 'goal_protein': 230.0,
            'goal_carbohydrates': 520.0, 'goal_fat': 110.0,
            'meal_names': [], 'meal_count': 0,
        },
        'competition_plan': {'found': False},
    }
    r = run_test("partial (off-season plan + macros, no meals or measurements)", fn,
                 make_env(partial_result), task_info,
                 expect_passed=False, score_min=15, score_max=59)
    all_pass = all_pass and r

    # Full completion
    full_result = {
        'weight_entries': {
            '2026-01-05': {'exists': True, 'weight_kg': 104.2},
            '2026-01-12': {'exists': True, 'weight_kg': 104.8},
            '2026-01-19': {'exists': True, 'weight_kg': 105.3},
            '2026-01-26': {'exists': True, 'weight_kg': 105.6},
            '2026-02-02': {'exists': True, 'weight_kg': 106.1},
            '2026-02-09': {'exists': True, 'weight_kg': 106.4},
            '2026-02-16': {'exists': True, 'weight_kg': 105.8},
            '2026-02-23': {'exists': True, 'weight_kg': 104.9},
        },
        'measurement_data': {
            'Body Fat Percentage': {
                'exists': True, 'unit': '%',
                'entries': {'2026-01-08': 18.4, '2026-02-05': 17.9, '2026-03-05': 17.2}
            },
            'Lean Body Mass': {
                'exists': True, 'unit': 'kg',
                'entries': {'2026-01-08': 85.1, '2026-02-05': 86.3, '2026-03-05': 87.8}
            },
            'Vertical Jump Height': {
                'exists': True, 'unit': 'cm',
                'entries': {'2026-01-08': 58, '2026-02-05': 61, '2026-03-05': 64}
            },
        },
        'offseason_plan': {
            'found': True,
            'goal_energy': 4200.0, 'goal_protein': 230.0,
            'goal_carbohydrates': 520.0, 'goal_fat': 110.0,
            'meal_names': ['Pre-Workout Fuel', 'Post-Workout Recovery', 'Breakfast',
                           'Lunch', 'Dinner', 'Evening Snack'],
            'meal_count': 6,
        },
        'competition_plan': {
            'found': True,
            'goal_energy': 2800.0, 'goal_protein': 260.0,
            'goal_carbohydrates': 280.0, 'goal_fat': 70.0,
            'meal_names': ['Morning Weigh-In Breakfast', 'Pre-Attempt Snack',
                           'Inter-Attempt Fuel', 'Post-Competition Recovery'],
            'meal_count': 4,
        },
    }
    r = run_test("full completion", fn, make_env(full_result), task_info,
                 expect_passed=True, score_min=60, score_max=100)
    all_pass = all_pass and r

    return all_pass


# ===========================================================================
# Task 4: corporate_health_screening_program
# ===========================================================================
def test_corporate_health_screening_program():
    print("\n=== corporate_health_screening_program ===")
    mod = load_verifier('corporate_health_screening_program')
    fn = mod.verify_corporate_health_screening_program
    task_info = {}
    all_pass = True

    # Do-nothing
    empty_result = {
        'users': [
            {'username': 'dwilliams_meridian', 'exists': False, 'email_correct': False, 'email_found': None},
            {'username': 'rparker_meridian', 'exists': False, 'email_correct': False, 'email_found': None},
            {'username': 'lchavez_meridian', 'exists': False, 'email_correct': False, 'email_found': None},
        ],
        'routine': {'found': False, 'description': None, 'days': []},
        'nutrition_plan': {'found': False},
        'measurement_categories': {
            'Waist Circumference': {'exists': False, 'unit': None},
            'Resting Heart Rate': {'exists': False, 'unit': None},
        },
    }
    r = run_test("do-nothing (empty result)", fn, make_env(empty_result), task_info,
                 expect_passed=False, score_min=0, score_max=0)
    all_pass = all_pass and r

    # Partial: users + routine + days (no macros, no meals, no categories)
    # Anti-pattern 4 check: this should NOT pass (< 70)
    partial_result = {
        'users': [
            {'username': 'dwilliams_meridian', 'exists': True, 'email_correct': True,
             'email_found': 'd.williams@meridian-ind.com'},
            {'username': 'rparker_meridian', 'exists': True, 'email_correct': True,
             'email_found': 'r.parker@meridian-ind.com'},
            {'username': 'lchavez_meridian', 'exists': True, 'email_correct': True,
             'email_found': 'l.chavez@meridian-ind.com'},
        ],
        'routine': {
            'found': True,
            'description': '12-week cardiovascular risk reduction program for sedentary manufacturing workers',
            'days': [
                {'name': 'Cardio and Core Activation', 'day_of_week': [1], 'exercises': ['Walking', 'Plank']},
                {'name': 'Upper Body Resistance', 'day_of_week': [3], 'exercises': ['Dumbbell Lateral Raise', 'Push-up']},
                {'name': 'Lower Body Mobility and Strength', 'day_of_week': [5], 'exercises': ['Squats', 'Lunges']},
            ]
        },
        'nutrition_plan': {
            'found': True,
            'goal_energy': 0, 'goal_protein': 0, 'goal_carbohydrates': 0, 'goal_fat': 0,
            'meal_names': [], 'meal_count': 0,
        },
        'measurement_categories': {
            'Waist Circumference': {'exists': False, 'unit': None},
            'Resting Heart Rate': {'exists': False, 'unit': None},
        },
    }
    # C1=18, C2=9, C3=10, C4=9, C5=6, C6=4, C7=10, C8=0, C9=0, C10=0, C11=0 = 66 < 70
    r = run_test("partial (users+routine+days+plan, no macros/meals/categories) [AP4 check]",
                 fn, make_env(partial_result), task_info,
                 expect_passed=False, score_min=50, score_max=69)
    all_pass = all_pass and r

    # Full completion
    full_result = {
        'users': [
            {'username': 'dwilliams_meridian', 'exists': True, 'email_correct': True,
             'email_found': 'd.williams@meridian-ind.com'},
            {'username': 'rparker_meridian', 'exists': True, 'email_correct': True,
             'email_found': 'r.parker@meridian-ind.com'},
            {'username': 'lchavez_meridian', 'exists': True, 'email_correct': True,
             'email_found': 'l.chavez@meridian-ind.com'},
        ],
        'routine': {
            'found': True,
            'description': '12-week cardiovascular risk reduction program for sedentary manufacturing workers',
            'days': [
                {'name': 'Cardio and Core Activation', 'day_of_week': [1], 'exercises': ['Walking', 'Plank']},
                {'name': 'Upper Body Resistance', 'day_of_week': [3],
                 'exercises': ['Dumbbell Lateral Raise', 'Push-up']},
                {'name': 'Lower Body Mobility and Strength', 'day_of_week': [5], 'exercises': ['Squats', 'Lunges']},
            ]
        },
        'nutrition_plan': {
            'found': True,
            'goal_energy': 2200.0, 'goal_protein': 110.0,
            'goal_carbohydrates': 270.0, 'goal_fat': 62.0,
            'meal_names': ['Whole-Grain Breakfast', 'Mid-Morning Snack', 'Balanced Lunch',
                           'Pre-Workout Snack', 'Heart-Healthy Dinner'],
            'meal_count': 5,
        },
        'measurement_categories': {
            'Waist Circumference': {'exists': True, 'unit': 'cm'},
            'Resting Heart Rate': {'exists': True, 'unit': 'bpm'},
        },
    }
    r = run_test("full completion", fn, make_env(full_result), task_info,
                 expect_passed=True, score_min=70, score_max=100)
    all_pass = all_pass and r

    return all_pass


# ===========================================================================
# Task 5: research_cohort_fitness_baseline
# ===========================================================================
def test_research_cohort_fitness_baseline():
    print("\n=== research_cohort_fitness_baseline ===")
    mod = load_verifier('research_cohort_fitness_baseline')
    fn = mod.verify_research_cohort_fitness_baseline
    task_info = {}
    all_pass = True

    # Do-nothing
    empty_result = {
        'users': [
            {'username': u, 'exists': False, 'email_correct': False, 'email_found': None}
            for u in ['stride26_p001', 'stride26_p002', 'stride26_p003', 'stride26_p004']
        ],
        'measurement_data': {
            'VO2max Estimate': {'exists': False, 'unit': None, 'entries': {}},
            'Handgrip Strength': {'exists': False, 'unit': None, 'entries': {}},
            'Single-Leg Balance Time': {'exists': False, 'unit': None, 'entries': {}},
        },
        'routine': {'found': False, 'description': None, 'days': []},
        'nutrition_plan': {'found': False},
    }
    r = run_test("do-nothing (empty result)", fn, make_env(empty_result), task_info,
                 expect_passed=False, score_min=0, score_max=0)
    all_pass = all_pass and r

    # Partial: users + categories + routine/days, no entries or meals
    # AP4 check: users(28)+categories(12)+routine+days(25) = ~65 < 70
    partial_result = {
        'users': [
            {'username': 'stride26_p001', 'exists': True, 'email_correct': True,
             'email_found': 'participant001@stride26study.org'},
            {'username': 'stride26_p002', 'exists': True, 'email_correct': True,
             'email_found': 'participant002@stride26study.org'},
            {'username': 'stride26_p003', 'exists': True, 'email_correct': True,
             'email_found': 'participant003@stride26study.org'},
            {'username': 'stride26_p004', 'exists': True, 'email_correct': True,
             'email_found': 'participant004@stride26study.org'},
        ],
        'measurement_data': {
            'VO2max Estimate': {'exists': True, 'unit': 'ml/kg/min', 'entries': {}},
            'Handgrip Strength': {'exists': True, 'unit': 'kg', 'entries': {}},
            'Single-Leg Balance Time': {'exists': True, 'unit': 's', 'entries': {}},
        },
        'routine': {
            'found': True,
            'description': '52-week workplace fitness RCT: progressive moderate-intensity aerobic and functional strength protocol',
            'days': [
                {'name': 'Aerobic Conditioning', 'day_of_week': [2], 'exercises': ['Cycling', 'Running']},
                {'name': 'Functional Strength Training', 'day_of_week': [4], 'exercises': ['Squats', 'Lunges', 'Dumbbell Lateral Raise']},
                {'name': 'Active Mobility Session', 'day_of_week': [6], 'exercises': ['Walking']},
            ]
        },
        'nutrition_plan': {'found': False},
    }
    # C1(20)+C2(8)+C3(4)+C4(4)+C5(4)+C6(0)+C7(0)+C8(0)+C9(10)+C10(9)+C11(6)+C12(3)+C13(0)+C14(0) = 68
    r = run_test("partial (users+categories+routine+days, no entries or plan) [AP4 check]",
                 fn, make_env(partial_result), task_info,
                 expect_passed=False, score_min=50, score_max=69)
    all_pass = all_pass and r

    # Full completion
    full_result = {
        'users': [
            {'username': 'stride26_p001', 'exists': True, 'email_correct': True,
             'email_found': 'participant001@stride26study.org'},
            {'username': 'stride26_p002', 'exists': True, 'email_correct': True,
             'email_found': 'participant002@stride26study.org'},
            {'username': 'stride26_p003', 'exists': True, 'email_correct': True,
             'email_found': 'participant003@stride26study.org'},
            {'username': 'stride26_p004', 'exists': True, 'email_correct': True,
             'email_found': 'participant004@stride26study.org'},
        ],
        'measurement_data': {
            'VO2max Estimate': {
                'exists': True, 'unit': 'ml/kg/min',
                'entries': {'2026-02-02': 34.2, '2026-02-03': 41.8,
                            '2026-02-04': 28.9, '2026-02-05': 38.5}
            },
            'Handgrip Strength': {
                'exists': True, 'unit': 'kg',
                'entries': {'2026-02-02': 32.4, '2026-02-03': 38.1,
                            '2026-02-04': 29.6, '2026-02-05': 35.8}
            },
            'Single-Leg Balance Time': {
                'exists': True, 'unit': 's',
                'entries': {'2026-02-02': 18, '2026-02-03': 24,
                            '2026-02-04': 12, '2026-02-05': 21}
            },
        },
        'routine': {
            'found': True,
            'description': '52-week workplace fitness RCT: progressive moderate-intensity aerobic and functional strength protocol',
            'days': [
                {'name': 'Aerobic Conditioning', 'day_of_week': [2], 'exercises': ['Cycling', 'Running']},
                {'name': 'Functional Strength Training', 'day_of_week': [4],
                 'exercises': ['Squats', 'Lunges', 'Dumbbell Lateral Raise']},
                {'name': 'Active Mobility Session', 'day_of_week': [6], 'exercises': ['Walking']},
            ]
        },
        'nutrition_plan': {
            'found': True,
            'goal_energy': 2400.0, 'goal_protein': 120.0,
            'goal_carbohydrates': 310.0, 'goal_fat': 72.0,
            'meal_names': ['Standardized Breakfast', 'Standardized Lunch',
                           'Standardized Dinner', 'Post-Exercise Recovery'],
            'meal_count': 4,
        },
    }
    r = run_test("full completion", fn, make_env(full_result), task_info,
                 expect_passed=True, score_min=70, score_max=100)
    all_pass = all_pass and r

    return all_pass


if __name__ == '__main__':
    results = {}
    results['endurance_athlete_periodization'] = test_endurance_athlete_periodization()
    results['rehab_exercise_protocol'] = test_rehab_exercise_protocol()
    results['sports_nutrition_consultation'] = test_sports_nutrition_consultation()
    results['corporate_health_screening_program'] = test_corporate_health_screening_program()
    results['research_cohort_fitness_baseline'] = test_research_cohort_fitness_baseline()

    print("\n" + "=" * 60)
    print("OFFLINE VERIFIER TEST SUMMARY")
    print("=" * 60)
    total_passed = 0
    for task, passed in results.items():
        status = "ALL PASS" if passed else "FAILURES"
        print(f"  {task}: {status}")
        if passed:
            total_passed += 1

    print(f"\n{total_passed}/{len(results)} tasks fully pass offline tests")
    sys.exit(0 if total_passed == len(results) else 1)
