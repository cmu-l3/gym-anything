#!/bin/bash
set -e

echo "=== Setting up add_exercise_image task ==="
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Download a real reference image (from Wikimedia Commons)
mkdir -p /home/ga/Documents
echo "Downloading reference image..."
# Download a public domain push-up photo.
curl -sL "https://upload.wikimedia.org/wikipedia/commons/thumb/c/c1/Push_up.jpg/800px-Push_up.jpg" -o /home/ga/Documents/pushup_reference.jpg

# Fallback: if network fails, use a real system wallpaper image as the reference photo
if [ ! -s /home/ga/Documents/pushup_reference.jpg ]; then
    echo "Warning: Download failed, falling back to local system image..."
    cp /usr/share/backgrounds/gnome/adwaita-day.jpg /home/ga/Documents/pushup_reference.jpg 2>/dev/null || true
fi

# Set proper permissions for the agent
chown -R ga:ga /home/ga/Documents

# 2. Ensure "Standard Push-up" exercise exists in the DB with no images
echo "Seeding the specific exercise..."
cat > /tmp/setup_exercise.py << 'EOF'
from wger.exercises.models import Exercise, ExerciseCategory, Language, ExerciseImage

try:
    lang, _ = Language.objects.get_or_create(id=2, defaults={'short_name': 'en', 'full_name': 'English'})
    cat, _ = ExerciseCategory.objects.get_or_create(name='Chest')
    
    # Create the exercise
    ex, created = Exercise.objects.get_or_create(
        name='Standard Push-up',
        defaults={'language': lang, 'category': cat, 'description': 'A classic bodyweight chest exercise.'}
    )
    
    # Clean up any existing images to ensure initial state count is 0
    ExerciseImage.objects.filter(exercise=ex).delete()
    print(f"Prepared Exercise ID {ex.id}: 'Standard Push-up' (Images cleared)")
    
except Exception as e:
    print(f"Error seeding exercise: {e}")
EOF

docker cp /tmp/setup_exercise.py wger-web:/tmp/setup_exercise.py
docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/setup_exercise.py').read())"

# 3. Launch Firefox and navigate
wait_for_wger_page
launch_firefox_to "http://localhost/en/exercise/overview/" 5

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="