#!/bin/bash
# Configure default session based on installer selection
# Called by Calamares during installation

SESSION=${1:-luna-mode}
USER=${2:-$(id -un 1000 2>/dev/null || echo "")}

case "$SESSION" in
    luna-mode)
        mkdir -p /etc/sddm.conf.d
        cat > /etc/sddm.conf.d/autologin.conf << EOF
[Autologin]
User=$USER
Session=luna-mode
Relogin=false
EOF
        ;;
    plasma)
        mkdir -p /etc/sddm.conf.d
        cat > /etc/sddm.conf.d/autologin.conf << EOF
[Autologin]
User=$USER
Session=plasma
Relogin=false
EOF
        ;;
    none)
        # No autologin - user will see SDDM login screen
        rm -f /etc/sddm.conf.d/autologin.conf
        ;;
esac
