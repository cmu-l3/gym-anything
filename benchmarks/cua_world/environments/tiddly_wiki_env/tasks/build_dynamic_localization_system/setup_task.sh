#!/bin/bash
echo "=== Setting up build_dynamic_localization_system task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time

# Prepare the raw JSON translations file for the agent
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/translations.json << 'EOF'
{
  "welcome-en": "Welcome to the IT Support Portal",
  "welcome-es": "Bienvenido al Portal de Soporte de TI",
  "welcome-fr": "Bienvenue sur le portail d'assistance informatique",
  "submit_ticket-en": "Submit a New Ticket",
  "submit_ticket-es": "Enviar un nuevo ticket",
  "submit_ticket-fr": "Soumettre un nouveau ticket",
  "knowledge_base-en": "Browse Knowledge Base",
  "knowledge_base-es": "Explorar la base de conocimientos",
  "knowledge_base-fr": "Parcourir la base de connaissances",
  "contact_admin-en": "Contact Administrator",
  "contact_admin-es": "Contactar al administrador",
  "contact_admin-fr": "Contacter l'administrateur"
}
EOF
chown -R ga:ga /home/ga/Documents

# Verify TiddlyWiki is running
if curl -s http://localhost:8080/ > /dev/null 2>&1; then
    echo "TiddlyWiki server is running"
else
    echo "WARNING: TiddlyWiki server not accessible"
fi

# Ensure Firefox is focused on TiddlyWiki
DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="