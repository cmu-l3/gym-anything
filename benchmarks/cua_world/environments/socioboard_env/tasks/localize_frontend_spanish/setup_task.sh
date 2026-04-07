#!/bin/bash
echo "=== Setting up localize_frontend_spanish task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Provide the real-world translation glossary
cat << 'EOF' > /home/ga/es_translations.json
{
  "Email Address": "Correo electrónico",
  "Password": "Contraseña",
  "Remember Me": "Recuérdame",
  "Sign In": "Iniciar sesión",
  "Login": "Iniciar sesión",
  "Forgot Password?": "¿Has olvidado tu contraseña?",
  "Create an account": "Crear una cuenta"
}
EOF
chmod 644 /home/ga/es_translations.json

# Wait for Socioboard frontend to be ready
if ! wait_for_http "http://localhost/login" 120; then
  echo "ERROR: Socioboard not reachable at http://localhost/login"
  exit 1
fi

# Ensure default state (locale = en) just in case
cd /opt/socioboard/socioboard-web-php
sudo sed -i 's/^APP_LOCALE=.*/APP_LOCALE=en/' .env 2>/dev/null || true
sudo -u ga php artisan config:clear > /dev/null 2>&1 || true
sudo -u ga php artisan view:clear > /dev/null 2>&1 || true

# Start browser pointing to the login page
open_socioboard_page "http://localhost/login"
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="