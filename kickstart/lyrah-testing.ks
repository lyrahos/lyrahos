# Lyrah OS Kickstart - Testing Channel
# Includes additional debug and testing packages

%include lyrah-main.ks

%packages
strace
ltrace
gdb
valgrind
%end

%post
echo "BRANCH=testing" >> /etc/lyrah-release
%end
