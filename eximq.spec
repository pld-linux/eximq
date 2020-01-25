Summary:	Supervising process for Exim's queue runners
Name:		eximq
# look into eximq.pl
Version:	0.4
# date of eximq file edit
Release:	0.20041227.1
License:	GPL
Group:		Applications/Mail
# see homepage
Source0:	%{name}.pl
Source1:	%{name}.args
Source2:	%{name}.init
Source3:	%{name}.tmpfiles
URL:		http://eximconf.alioth.debian.org/
BuildRequires:	rpm-perlprov >= 4.1-13
Requires:	exim >= 2:4.00
BuildArch:	noarch
BuildRoot:	%{tmpdir}/%{name}-%{version}-root-%(id -u -n)

%description

%prep
%setup -q -T -c

%build

%install
rm -rf $RPM_BUILD_ROOT
install -d $RPM_BUILD_ROOT{/etc/{rc.d/init.d,mail},%{_sbindir},/var/run/eximq} \
	$RPM_BUILD_ROOT/usr/lib/tmpfiles.d

install %{SOURCE0} $RPM_BUILD_ROOT%{_sbindir}
install %{SOURCE1} $RPM_BUILD_ROOT%{_sysconfdir}/mail/eximq.args
install %{SOURCE2} $RPM_BUILD_ROOT/etc/rc.d/init.d/%{name}
install %{SOURCE3} $RPM_BUILD_ROOT/usr/lib/tmpfiles.d/%{name}.conf

%clean
rm -rf $RPM_BUILD_ROOT

%post
/sbin/chkconfig --add %{name}
%service %{name} restart "%{name} daemon"

%preun
if [ "$1" = "0" ]; then
	%service %{name} stop
	/sbin/chkconfig --del %{name}
fi

%files
%defattr(644,root,root,755)
%attr(755,root,root) %{_sbindir}/eximq.pl
%attr(640,root,root) %config(noreplace) %verify(not md5 mtime size) %{_sysconfdir}/mail/%{name}.args
%attr(754,root,root) /etc/rc.d/init.d/%{name}
/usr/lib/tmpfiles.d/%{name}.conf
%attr(755,exim,root) /var/run/eximq
