# Lyrah OS Kickstart - Stable Channel
#
# NOTE: luna-ui is built from source during the ISO build (phase 4 in
# build-iso.yml). It is NOT installed via dnf — the binary is compiled
# and placed directly into the rootfs.

%packages
@kde-desktop-environment
@development-tools
qt6-qtwebengine
gamescope
steam
heroic-games-launcher-bin    # FIX #32: Consistent package name with outline
lutris
bottles
# luna-ui                    # Built from source in build-iso.yml phase 4
wine-staging
dxvk
vkd3d
winetricks
protontricks
protonup-qt
gamemode
mangohud
corectrl
gh
xclip
logrotate
pipewire
wireplumber
sddm
%end

%post
# Configure Luna Mode session
systemctl enable sddm
mkdir -p /var/log/lyrah/{luna-mode,desktop-mode}/{sessions,crashes}
# Set SELinux to permissive for gaming
sed -i 's/SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
%end
