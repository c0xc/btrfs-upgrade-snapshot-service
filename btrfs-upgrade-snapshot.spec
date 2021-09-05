Name:           btrfs-upgrade-snapshot
Version:        1
Release:        1
Summary:        Auto-snapshot creation on system(d) upgrade
Packager:       Paketmeister
License:        GPL
BuildArch:      noarch
BuildRoot:      %{_tmppath}/buildroot-%{name}-%{version}_%{release}
Requires:       bash
Prefix:         /usr/local/sbin

%description
Provides btrfs-upgrade-snapshot script.

%prep

%build
# nothing to do

%install
mkdir -p $RPM_BUILD_ROOT/etc/systemd/system
install -m 644 %{_sourcedir}/btrfs-os-snapshot.service $RPM_BUILD_ROOT/etc/systemd/system
mkdir -p $RPM_BUILD_ROOT/usr/local/sbin
install -m 755 %{_sourcedir}/btrfs-os-snapshot.sh $RPM_BUILD_ROOT/usr/local/sbin/btrfs-os-snapshot

%clean
rm -rfv $RPM_BUILD_ROOT

%pre

%post
systemctl daemon-reload
systemctl enable btrfs-os-snapshot

%postun
systemctl disable btrfs-os-snapshot

%files
%defattr(0755, root, root, 0755)
/usr/local/sbin/btrfs-os-snapshot
/etc/systemd/system/btrfs-os-snapshot.service
%defattr(0600, root, root, 0750)
%defattr(0600, root, root, 0700)

