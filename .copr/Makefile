srpm:
	dnf install -y git rpm-build
	spectool -g -R luna-ui/luna-ui.spec
	rpmbuild -bs luna-ui/luna-ui.spec --define "_sourcedir $(pwd)" --define "_srcrpmdir $(outdir)"
