#!/bin/bash
set -e

echo "=== Installing R and RStudio Desktop ==="

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install base dependencies
echo "Installing base dependencies..."
apt-get install -y \
    wget \
    curl \
    gnupg \
    ca-certificates \
    software-properties-common \
    apt-transport-https \
    dirmngr \
    gdebi-core

# Install GUI automation tools (needed for testing)
echo "Installing GUI automation tools..."
apt-get install -y \
    xdotool \
    wmctrl \
    scrot \
    imagemagick \
    python3-pip

# Install common R dependencies for packages BEFORE installing R
# This ensures all packages can be compiled properly
echo "Installing R package build dependencies..."
apt-get install -y \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libfontconfig1-dev \
    libfreetype6-dev \
    libfreetype-dev \
    libpng-dev \
    libtiff5-dev \
    libjpeg-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    libgit2-dev \
    libssh2-1-dev \
    pandoc \
    texlive-latex-base \
    texlive-fonts-recommended \
    pkg-config \
    cmake \
    build-essential

# Install R from CRAN repository
echo "Installing R from CRAN..."

# Add CRAN GPG key and repository for Ubuntu 22.04 (Jammy)
wget -qO- https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc | tee -a /etc/apt/trusted.gpg.d/cran_ubuntu_key.asc

# Add R 4.x repository
add-apt-repository -y "deb https://cloud.r-project.org/bin/linux/ubuntu $(lsb_release -cs)-cran40/"

# Update and install R
apt-get update
apt-get install -y r-base r-base-dev

# Verify R installation
echo "Verifying R installation..."
R --version
R_VERSION=$(R --version | head -1 | grep -oP 'R version \K[0-9]+\.[0-9]+')
echo "R major.minor version: $R_VERSION"

# Download and install RStudio Desktop
# Use the latest stable version that works with R 4.x
echo "Downloading RStudio Desktop..."
cd /tmp

# Try multiple RStudio versions (most recent first)
# Need RStudio 2024.12+ for R 4.5 compatibility
# RStudio 2024.12.1-563 is confirmed to work with R 4.5.2
RSTUDIO_VERSIONS=(
    "2024.12.1-563"
    "2024.12.0-467"
    "2025.06.0-496"
)

RSTUDIO_INSTALLED=false
for VERSION in "${RSTUDIO_VERSIONS[@]}"; do
    RSTUDIO_DEB="rstudio-${VERSION}-amd64.deb"
    RSTUDIO_URL="https://download1.rstudio.org/electron/jammy/amd64/${RSTUDIO_DEB}"
    echo "Trying RStudio version ${VERSION}..."

    if wget -q --timeout=30 -O "${RSTUDIO_DEB}" "${RSTUDIO_URL}" 2>/dev/null; then
        if [ -f "${RSTUDIO_DEB}" ] && [ -s "${RSTUDIO_DEB}" ]; then
            echo "Downloaded ${RSTUDIO_DEB}, installing..."
            if gdebi -n "${RSTUDIO_DEB}"; then
                RSTUDIO_INSTALLED=true
                echo "RStudio ${VERSION} installed successfully"
                rm -f "${RSTUDIO_DEB}"
                break
            fi
        fi
    fi
    rm -f "${RSTUDIO_DEB}"
done

if [ "$RSTUDIO_INSTALLED" = false ]; then
    echo "All RStudio versions failed. Trying apt package..."
    apt-get install -y rstudio || {
        echo "Failed to install RStudio from any source"
        exit 1
    }
fi

# Verify RStudio installation
echo "Verifying RStudio installation..."
which rstudio
rstudio --version 2>/dev/null || echo "RStudio installed (version check may fail without display)"

# Install essential R packages system-wide
# Install in order of dependencies: base packages first, then tidyverse
echo "Installing essential R packages..."

# First install individual packages that tidyverse depends on
R -e "install.packages(c('ggplot2', 'dplyr', 'readr', 'tibble', 'tidyr', 'purrr', 'stringr', 'forcats'), repos='https://cloud.r-project.org/', Ncpus=4)"

# Then try tidyverse (may fail on ragg, but that's optional)
R -e "tryCatch(install.packages('tidyverse', repos='https://cloud.r-project.org/', Ncpus=4), error=function(e) message('tidyverse install warning: ', e\$message))" || true

# Install other useful packages
R -e "install.packages(c('knitr', 'rmarkdown'), repos='https://cloud.r-project.org/', Ncpus=4)" || true

# Create user R library directory
mkdir -p /home/ga/R/library
chown -R ga:ga /home/ga/R

# Set R library path in Renviron
cat > /home/ga/.Renviron << 'EOF'
R_LIBS_USER=/home/ga/R/library
EOF
chown ga:ga /home/ga/.Renviron

# Verify ggplot2 is installed (critical for our tasks)
echo "Verifying ggplot2 installation..."
R -e "library(ggplot2); print('ggplot2 loaded successfully')"

echo "=== R and RStudio installation complete ==="
