# Lyrah OS Kickstart - Development Channel
# Includes full development toolchain

%include lyrah-main.ks

%packages
@development-tools
cmake
gcc-c++
qt6-qtbase-devel
qt6-qtdeclarative-devel
SDL2-devel
sqlite-devel
rpm-build
mock
%end

%post
echo "BRANCH=dev" >> /etc/lyrah-release
%end
