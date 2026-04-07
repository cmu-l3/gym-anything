#!/bin/bash
set -e
echo "=== Setting up add_exercise_aliases task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for wger web service to be fully responsive
wait_for_wger_page

echo "Ensuring required database state..."
# Use django_shell to ensure the 3 exercises exist exactly as named, and clean up any pre-existing aliases or fake exercises to ensure a clean starting state.
django_shell "
import sys
from wger.exercises.models import Exercise, ExerciseAlias, ExerciseCategory
from wger.core.models import Language

try:
    # Ensure English language exists
    lang, _ = Language.objects.get_or_create(id=2, defaults={'full_name': 'English', 'short_name': 'en'})
    
    # Ensure some categories exist
    cat_legs, _ = ExerciseCategory.objects.get_or_create(name='Legs')
    cat_arms, _ = ExerciseCategory.objects.get_or_create(name='Arms')
    
    # 1. CLEANUP: Delete any existing aliases or fake exercises that would game the task
    ExerciseAlias.objects.filter(alias__in=['RDL', 'OHP', 'BSS']).delete()
    Exercise.objects.filter(name__in=['RDL', 'OHP', 'BSS']).delete()
    
    # 2. SEED: Ensure the base exercises exist exactly as named
    Exercise.objects.get_or_create(name='Romanian Deadlift', defaults={'category': cat_legs, 'language': lang})
    Exercise.objects.get_or_create(name='Overhead Press', defaults={'category': cat_arms, 'language': lang})
    Exercise.objects.get_or_create(name='Bulgarian Split Squat', defaults={'category': cat_legs, 'language': lang})
    
    print('Database state prepared successfully.')
except Exception as e:
    print(f'Error setting up database: {e}')
"

# Launch Firefox to the Exercises Overview page
launch_firefox_to "http://localhost/en/exercise/overview/" 5

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="