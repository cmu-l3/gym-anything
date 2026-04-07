#!/bin/bash
# NOTE: Do NOT use set -e here - we need careful exit control
# PRE_START HOOK: Pre-install packages and download installer.
# The actual Virtualmin installer runs in post_start (foreground).

echo "=== install_virtualmin.sh (pre_start) ==="

export DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------------
# Helper: retry a command up to N times with backoff
# ---------------------------------------------------------------
retry() {
    local max_attempts="$1"
    shift
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        if "$@"; then
            return 0
        fi
        echo "  Attempt $attempt/$max_attempts failed"
        if [ $attempt -lt $max_attempts ]; then
            local wait=$((attempt * 10))
            echo "  Retrying in ${wait}s..."
            sleep $wait
        fi
        attempt=$((attempt + 1))
    done
    return 1
}

# ---------------------------------------------------------------
# Helper: wait for apt/dpkg locks, fix broken state
# ---------------------------------------------------------------
wait_for_apt_lock() {
    local timeout=120
    local elapsed=0
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
          fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || \
          fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do
        if [ $elapsed -ge $timeout ]; then
            echo "WARNING: apt lock held for ${timeout}s, forcing release"
            rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock \
                  /var/lib/apt/lists/lock /var/cache/apt/archives/lock 2>/dev/null
            dpkg --configure -a 2>/dev/null || true
            break
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    dpkg --configure -a 2>/dev/null || true
}

# ---------------------------------------------------------------
# IDEMPOTENCY CHECK
# ---------------------------------------------------------------
if which virtualmin > /dev/null 2>&1 && [ -f /home/ga/virtualmin-install-done ]; then
    echo "=== Virtualmin already installed. Skipping. ==="
    echo "root:GymAnything123!" | chpasswd
    hostnamectl set-hostname virtualmin.gym-anything.local 2>/dev/null || true
    which xdotool > /dev/null 2>&1 || apt-get install -y xdotool wmctrl scrot imagemagick x11-utils xclip python3-pip 2>/dev/null
    exit 0
fi

# ---------------------------------------------------------------
# 1. Set root password and hostname
# ---------------------------------------------------------------
echo "root:GymAnything123!" | chpasswd
hostnamectl set-hostname virtualmin.gym-anything.local
grep -q "virtualmin.gym-anything.local" /etc/hosts || \
    echo "127.0.1.1 virtualmin.gym-anything.local virtualmin" >> /etc/hosts
echo "--- Hostname: $(hostname -f 2>/dev/null || echo unknown) ---"

# ---------------------------------------------------------------
# 2. Install prerequisites and GUI tools (foreground, with retry)
# ---------------------------------------------------------------
echo "--- Installing prerequisites and GUI tools ---"
wait_for_apt_lock
retry 3 apt-get update

wait_for_apt_lock
retry 3 apt-get install -y \
    curl wget ca-certificates perl gnupg \
    xdotool wmctrl scrot imagemagick x11-utils xclip python3-pip

# ---------------------------------------------------------------
# 3. Pre-install heavy LAMP stack packages (foreground, with retry)
#    This dramatically reduces the Virtualmin installer time from
#    30-60 minutes to 5-15 minutes by having packages already present.
# ---------------------------------------------------------------
echo "--- Pre-installing LAMP stack packages ---"

wait_for_apt_lock
retry 3 apt-get install -y \
    apache2 libapache2-mod-fcgid \
    || echo "WARNING: Some Apache packages failed"

wait_for_apt_lock
retry 3 apt-get install -y \
    mariadb-server mariadb-client \
    || echo "WARNING: MariaDB packages failed"

wait_for_apt_lock
retry 3 apt-get install -y \
    php php-fpm php-mysql php-gd php-curl php-xml php-mbstring php-zip php-intl php-common \
    || echo "WARNING: Some PHP packages failed"

wait_for_apt_lock
retry 3 apt-get install -y \
    bind9 bind9-utils \
    postfix \
    dovecot-core dovecot-imapd dovecot-pop3d \
    || echo "WARNING: Some mail/DNS packages failed"

wait_for_apt_lock
apt-get install -y \
    proftpd-basic spamassassin spamc procmail quota quotatool libapache2-mod-php \
    2>/dev/null || echo "WARNING: Some optional packages failed (non-critical)"

echo "--- Heavy packages pre-installed ---"

# ---------------------------------------------------------------
# 4. Download the Virtualmin installer (with retry + multiple mirrors)
#    Saved to /tmp/virtualmin-install.sh for post_start to run.
# ---------------------------------------------------------------
echo "--- Downloading Virtualmin installer ---"
date > /home/ga/virtualmin-install-start
chmod 644 /home/ga/virtualmin-install-start

INSTALLER_DOWNLOADED=false
for url in \
    "https://software.virtualmin.com/gpl/scripts/virtualmin-install.sh" \
    "https://raw.githubusercontent.com/virtualmin/virtualmin-install/master/virtualmin-install.sh" \
    "https://download.virtualmin.com/virtualmin-install.sh"; do
    echo "  Trying: $url"
    for attempt in 1 2 3; do
        if curl -fsSL --connect-timeout 30 --max-time 120 "$url" \
                -o /tmp/virtualmin-install.sh 2>/dev/null; then
            FSIZE=$(wc -c < /tmp/virtualmin-install.sh 2>/dev/null || echo 0)
            if [ "$FSIZE" -gt 10000 ]; then
                echo "--- Downloaded installer ($FSIZE bytes) ---"
                chmod +x /tmp/virtualmin-install.sh
                INSTALLER_DOWNLOADED=true
                break 2
            fi
        fi
        sleep 5
    done
done

if $INSTALLER_DOWNLOADED; then
    echo "--- Installer ready at /tmp/virtualmin-install.sh ---"
else
    echo "WARNING: Could not download installer from any mirror"
fi

echo "=== install_virtualmin.sh complete ==="
