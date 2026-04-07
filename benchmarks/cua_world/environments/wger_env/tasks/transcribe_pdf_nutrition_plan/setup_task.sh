#!/bin/bash
set -e
echo "=== Setting up transcribe_pdf_nutrition_plan task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

wait_for_wger_page

# 1. Pre-populate the required ingredients into the wger DB
echo "Seeding necessary ingredients..."
cat > /tmp/wger_add_ingredients.py << 'EOF'
from wger.nutrition.models import Ingredient
from django.contrib.auth.models import User

try:
    admin = User.objects.get(username='admin')
    items = [
        ('Rolled Oats', 389, 16.9, 66.3, 6.9),
        ('Whole Milk', 61, 3.2, 4.8, 3.3),
        ('Chicken Breast (Raw)', 120, 22.5, 0, 2.6),
        ('Brown Rice', 111, 2.6, 23.0, 0.9),
        ('Broccoli', 34, 2.8, 6.6, 0.4),
        ('Beef Steak', 271, 25.0, 0, 19.0),
        ('Sweet Potato', 86, 1.6, 20.1, 0.1)
    ]

    for name, energy, protein, carbs, fat in items:
        Ingredient.objects.get_or_create(
            name=name,
            defaults={
                'user': admin,
                'energy': energy,
                'protein': protein,
                'carbohydrates': carbs,
                'fat': fat,
                'status': '2'
            }
        )
    print("Ingredients verified/added.")
except Exception as e:
    print(f"Error seeding ingredients: {e}")
EOF

docker cp /tmp/wger_add_ingredients.py wger-web:/tmp/wger_add_ingredients.py
docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/wger_add_ingredients.py').read())"

# 2. Install reportlab for PDF generation (Debian package is safest)
echo "Installing python3-reportlab..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null && apt-get install -y -qq python3-reportlab >/dev/null

# 3. Generate the PDF document using Python
echo "Generating nutrition protocol PDF..."
cat > /tmp/make_pdf.py << 'EOF'
from reportlab.lib.pagesizes import letter
from reportlab.pdfgen import canvas
import os

os.makedirs("/home/ga/Documents", exist_ok=True)
pdf_path = "/home/ga/Documents/nutrition_protocol.pdf"

c = canvas.Canvas(pdf_path, pagesize=letter)
c.setFont("Helvetica-Bold", 20)
c.drawString(50, 750, "Daily Nutrition Protocol")

c.setFont("Helvetica", 12)
c.drawString(50, 720, "Client: Admin User")
c.drawString(50, 700, "Goal: Lean Muscle Gain")
c.drawString(50, 680, "Instructions: Follow these exact macro measurements daily.")

c.setFont("Helvetica-Bold", 14)
c.drawString(50, 630, "Meal 1: Breakfast")
c.setFont("Helvetica", 12)
c.drawString(70, 610, "• Rolled Oats: 80g")
c.drawString(70, 590, "• Whole Milk: 250g")

c.setFont("Helvetica-Bold", 14)
c.drawString(50, 540, "Meal 2: Lunch")
c.setFont("Helvetica", 12)
c.drawString(70, 520, "• Chicken Breast (Raw): 200g")
c.drawString(70, 500, "• Brown Rice: 150g")
c.drawString(70, 480, "• Broccoli: 100g")

c.setFont("Helvetica-Bold", 14)
c.drawString(50, 430, "Meal 3: Dinner")
c.setFont("Helvetica", 12)
c.drawString(70, 410, "• Beef Steak: 250g")
c.drawString(70, 390, "• Sweet Potato: 200g")

c.save()
print(f"PDF generated at {pdf_path}")
EOF

python3 /tmp/make_pdf.py
chown ga:ga /home/ga/Documents/nutrition_protocol.pdf
chmod 644 /home/ga/Documents/nutrition_protocol.pdf

# 4. Launch Firefox to the wger login page
launch_firefox_to "http://localhost/en/user/login" 5

# 5. Take initial evidence screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="