#!/bin/bash

set -e  # Exit script on error
set -u  # Treat unset variables as an error
set -o pipefail  # Catch errors in pipelines

log_message() {
    echo -e "[INFO] $1"
}

exit_with_error() {
    echo -e "[ERROR] $1" >&2
    exit 1
}

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
    exit_with_error "This script must be run as root. Use sudo."
fi

# Locate the correct Netplan configuration file
NETPLAN_CONFIG=$(find /etc/netplan/ -type f -name "*.yaml" | head -n 1)
if [[ -z "$NETPLAN_CONFIG" ]]; then
    exit_with_error "No Netplan configuration file found in /etc/netplan/"
fi

# Check and update Netplan settings if necessary
if grep -q "192.168.16.21/24" "$NETPLAN_CONFIG"; then
    log_message "Netplan configuration is already set."
else
    log_message "Updating Netplan configuration in $NETPLAN_CONFIG."
    chmod 600 "$NETPLAN_CONFIG"
    cat > "$NETPLAN_CONFIG" <<EOL
network:
  ethernets:
    eth0:
      dhcp4: no
      addresses:
        - 192.168.16.21/24
      routes:
        - to: default
          via: 192.168.16.2
  version: 2
EOL
    chmod 644 "$NETPLAN_CONFIG"
    netplan apply || exit_with_error "Failed to apply Netplan configuration."
fi

# Update the /etc/hosts file
HOSTS_FILE="/etc/hosts"
if grep -q "192.168.16.21 server1" "$HOSTS_FILE"; then
    log_message "/etc/hosts is already configured."
else
    log_message "Updating /etc/hosts file."
    sed -i '/server1/d' "$HOSTS_FILE"
    echo "192.168.16.21 server1" >> "$HOSTS_FILE"
fi

# Install necessary packages
log_message "Installing required software packages."
apt update -y && apt install -y apache2 squid || exit_with_error "Failed to install required software."

# Enable and start Apache and Squid services
log_message "Enabling and starting services."
systemctl enable --now apache2 squid || exit_with_error "Failed to start required services."

# List of users to be created
USER_LIST=("dennis" "aubrey" "captain" "snibbles" "brownie" "scooter" "sandy" "perrier" "cindy" "tiger" "yoda")

# Configure user accounts
for USER in "${USER_LIST[@]}"; do
    if id "$USER" &>/dev/null; then
        log_message "User $USER already exists."
    else
        log_message "Creating user $USER."
        useradd -m -s /bin/bash "$USER" || exit_with_error "Failed to create user $USER."
    fi

    # Define user home directory and SSH configuration
    HOME_DIR="/home/$USER"
    SSH_FOLDER="$HOME_DIR/.ssh"
    mkdir -p "$SSH_FOLDER"
    chown "$USER:$USER" "$SSH_FOLDER"
    chmod 700 "$SSH_FOLDER"

    # Generate RSA SSH key if missing
    if [[ ! -f "$SSH_FOLDER/id_rsa.pub" ]]; then
        log_message "Generating RSA SSH key for $USER."
        sudo -u "$USER" ssh-keygen -t rsa -b 4096 -N "" -f "$SSH_FOLDER/id_rsa"
    fi

    # Generate Ed25519 SSH key if missing
    if [[ ! -f "$SSH_FOLDER/id_ed25519.pub" ]]; then
        log_message "Generating Ed25519 SSH key for $USER."
        sudo -u "$USER" ssh-keygen -t ed25519 -N "" -f "$SSH_FOLDER/id_ed25519"
    fi

    # Concatenate SSH keys into authorized_keys
    cat "$SSH_FOLDER/id_rsa.pub" "$SSH_FOLDER/id_ed25519.pub" > "$SSH_FOLDER/authorized_keys"
    chown "$USER:$USER" "$SSH_FOLDER/authorized_keys"
    chmod 600 "$SSH_FOLDER/authorized_keys"
done

# Special configuration for the user 'dennis'
if id "dennis" &>/dev/null; then
    log_message "Granting sudo privileges to dennis."
    usermod -aG sudo dennis
    echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG4rT3vTt99Ox5kndS4HmgTrKBT8SKzhK4rhGkEVGlCI student@generic-vm" >> "/home/dennis/.ssh/authorized_keys"
fi

log_message "Script execution completed successfully."
