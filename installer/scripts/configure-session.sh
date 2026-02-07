#!/bin/bash
# Configure default session for installed system
# Called by Calamares during installation

SESSION=${1:-plasma}
USER=${2:-$(id -un 1000 2>/dev/null || echo "")}

mkdir -p /etc/sddm.conf.d

case "$SESSION" in
    none)
        # Explicit opt-out for compatibility with older flows
        rm -f /etc/sddm.conf.d/autologin.conf
        ;;
    plasma|luna-mode|*)
        # Plasma is now the default installer session target
        cat > /etc/sddm.conf.d/autologin.conf << EOF2
[Autologin]
User=$USER
Session=plasma
Relogin=false
EOF2
        ;;
esac
