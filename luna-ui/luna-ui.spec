Name:           luna-ui
Version:        1.0.0
Release:        1%{?dist}
Summary:        Lyrah OS Gaming Frontend
License:        MIT

# FIX #25: Proper source configuration for Copr builds
# Source tarball is created from the GitHub repository via spectool or Copr webhook
Source0:        https://github.com/lyrah-os/lyrah-os/archive/v%{version}/%{name}-%{version}.tar.gz

BuildRequires:  cmake gcc-c++ qt6-qtbase-devel qt6-qtdeclarative-devel qt6-qtwebsockets-devel SDL2-devel sqlite-devel
Requires:       qt6-qtbase qt6-qtdeclarative qt6-qtwebsockets SDL2 sqlite
Requires:       google-noto-sans-fonts
Requires:       xdotool
Requires:       pipx

%description
Custom store-agnostic gaming frontend for Lyrah OS Luna Mode.
Aggregates games from Steam, Epic, GOG, Lutris, and more into
a unified, controller-friendly interface.

%prep
%autosetup -n lyrah-os-%{version}
cd luna-ui

%build
cd luna-ui
%cmake
%cmake_build

%install
cd luna-ui
%cmake_install
mkdir -p %{buildroot}/usr/share/luna-ui/themes
cp -r resources/themes/* %{buildroot}/usr/share/luna-ui/themes/
mkdir -p %{buildroot}/usr/share/luna-ui/fonts
cp -r resources/fonts/* %{buildroot}/usr/share/luna-ui/fonts/ 2>/dev/null || true
mkdir -p %{buildroot}/usr/share/luna-ui/icons
cp -r resources/icons/* %{buildroot}/usr/share/luna-ui/icons/ 2>/dev/null || true

%files
/usr/bin/luna-ui
/usr/share/luna-ui/

%changelog
* Tue Feb 04 2026 Builder <builder@lyrah.os> - 1.0.0-1
- Initial package
