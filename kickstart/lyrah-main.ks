# Lyrah OS Kickstart - Stable Channel
#
# NOTE (FIX #35): The `luna-ui` package must be built and published to the
# lyrah/lyrah-os Copr repository BEFORE this kickstart can be used.
# Build luna-ui first, push to Copr, then enable here.

%packages
@kde-desktop-environment
@development-tools
gamescope
steam
heroic-games-launcher-bin    # FIX #32: Consistent package name with outline
lutris
bottles
# luna-ui                    # Uncomment after publishing to Copr
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
