#!/bin/bash
echo "=== Setting up tag_exercise_equipment task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Wait for application to be available
wait_for_wger_page

# Set up specific exercise state via Django ORM
echo "Provisioning specific database state..."
django_shell "
import sys
from wger.exercises.models import Exercise, Equipment, ExerciseCategory
from wger.core.models import Language

try:
    # Get standard language and category fallbacks
    lang = Language.objects.filter(short_name='en').first() or Language.objects.first()
    cat = ExerciseCategory.objects.first()
    
    # Ensure standard required equipment exists in the system
    barbell, _ = Equipment.objects.get_or_create(name='Barbell')
    bench, _ = Equipment.objects.get_or_create(name='Bench')
    
    # Create the target exercise explicitly
    exercise, created = Exercise.objects.get_or_create(
        name='Barbell Hip Thrust (Sports Science)',
        defaults={
            'category': cat,
            'description': 'A lower body compound exercise focusing on gluteal activation.',
            'language': lang
        }
    )
    
    # ENFORCE INITIAL STATE: Clear any other equipment, link ONLY the Barbell
    exercise.equipment.set([barbell])
    print(f'SETUP_SUCCESS: Exercise ID {exercise.id} initialized with [Barbell]')
except Exception as e:
    print('SETUP_ERROR:', e)
"

# Launch Firefox and load the login page
launch_firefox_to "http://localhost/en/user/login" 5

echo "Capturing initial state screenshot..."
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="