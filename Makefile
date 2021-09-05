###############
PWD=$(shell pwd)
SPEC=btrfs-upgrade-snapshot.spec

all: rpmbuild

rpmbuild:
	/bin/bash -c "mkdir -p $(PWD)/rpmbuild/{BUILD,SOURCES,SRPMS,SPECS,RPMS/noarch,RPMS/x86_64}"
	cp -rp $(PWD)/os-snapshot-service/btrfs-os-snapshot.service $(PWD)/rpmbuild/SOURCES/
	cp -rp $(PWD)/os-snapshot-service/btrfs-os-snapshot.sh $(PWD)/rpmbuild/SOURCES/
	cp -rp $(PWD)/$(SPEC) $(PWD)/rpmbuild/SPECS/
	rpmbuild --define "_topdir $(PWD)/rpmbuild" -bb --clean $(PWD)/rpmbuild/SPECS/$(SPEC)

rpm: rpmbuild
	ls -lrth $(PWD)/rpmbuild/RPMS/*/*.rpm

clean:
	rm -rfv $(PWD)/rpmbuild/

