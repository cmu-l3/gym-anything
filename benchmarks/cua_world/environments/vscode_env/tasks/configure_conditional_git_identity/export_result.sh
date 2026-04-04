#!/bin/bash
# set -euo pipefail

echo "=== Exporting Configure Conditional Git Identity Result ==="

# Export global gitconfig
if [ -f /home/ga/.gitconfig ]; then
    echo "Exporting ~/.gitconfig..."
    cp /home/ga/.gitconfig /tmp/gitconfig_global.txt
else
    echo "No ~/.gitconfig found" > /tmp/gitconfig_global.txt
fi

# Export personal identity include file
if [ -f /home/ga/.config/git/personal-identity.inc ]; then
    echo "Exporting personal-identity.inc..."
    cp /home/ga/.config/git/personal-identity.inc /tmp/personal_identity_inc.txt
else
    echo "No personal-identity.inc found" > /tmp/personal_identity_inc.txt
fi

# Export company identity include file
if [ -f /home/ga/.config/git/company-identity.inc ]; then
    echo "Exporting company-identity.inc..."
    cp /home/ga/.config/git/company-identity.inc /tmp/company_identity_inc.txt
else
    echo "No company-identity.inc found" > /tmp/company_identity_inc.txt
fi

# Test git config resolution in each directory
echo "Testing git config resolution..."

# Test personal directory
cd /home/ga/workspace/personal-projects/my-oss-lib 2>/dev/null
if [ $? -eq 0 ]; then
    sudo -u ga git config user.email > /tmp/git_email_personal.txt 2>&1 || echo "error" > /tmp/git_email_personal.txt
    sudo -u ga git config user.name > /tmp/git_name_personal.txt 2>&1 || echo "error" > /tmp/git_name_personal.txt
else
    echo "error" > /tmp/git_email_personal.txt
    echo "error" > /tmp/git_name_personal.txt
fi

# Test company directory
cd /home/ga/workspace/company-work/proprietary-app 2>/dev/null
if [ $? -eq 0 ]; then
    sudo -u ga git config user.email > /tmp/git_email_company.txt 2>&1 || echo "error" > /tmp/git_email_company.txt
    sudo -u ga git config user.name > /tmp/git_name_company.txt 2>&1 || echo "error" > /tmp/git_name_company.txt
else
    echo "error" > /tmp/git_email_company.txt
    echo "error" > /tmp/git_name_company.txt
fi

echo "✅ Export complete"
echo "Configuration files exported to /tmp"
echo ""
echo "Personal email resolved to:"
cat /tmp/git_email_personal.txt
echo ""
echo "Company email resolved to:"
cat /tmp/git_email_company.txt