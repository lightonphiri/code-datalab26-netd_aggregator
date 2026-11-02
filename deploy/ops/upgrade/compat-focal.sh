#!/bin/bash
# Keep focal-built binaries running across the Ubuntu upgrade (session 05, November 2, 2026):
# copy the non-glibc libraries that the custom Orthanc build, its plugins and NETD's Ruby link to
# into /opt/compat-focal/lib, and give only orthanc-build and netd-portal LD_LIBRARY_PATH to it.
# Undo: rm the two drop-ins, systemctl daemon-reload, restart; rm -r /opt/compat-focal.
set -Eeuo pipefail
L=/opt/compat-focal/lib; mkdir -p $L
O=/home/emiproject/work_package-2/pacs-orthanc/orthanc
{ echo $O/Build/Orthanc; ls $O/OrthancServer/Plugins/*.so; echo /opt/netd/ruby/bin/ruby;
  find /opt/netd/ruby /opt/netd/portal/vendor -name '*.so*' -type f; } > /tmp/compat-bins.txt
# glibc itself and the toolchain runtime stay system-provided (newer versions are backward compatible)
SKIP='^(libc|libm|libpthread|libdl|librt|libresolv|libutil|libanl|libnsl|libcrypt|libstdc\+\+|libgcc_s|ld-linux-x86-64)\.so'
n=0
while read -r f; do
  ldd "$f" 2>/dev/null | awk '/=> \// {print $1, $3}'
done < /tmp/compat-bins.txt | sort -u | while read -r name path; do
  echo "$name" | grep -qE "$SKIP" && continue
  case "$path" in /lib/*|/usr/lib/*) ;; *) continue;; esac
  [ -e "$L/$name" ] || { cp -L "$path" "$L/$name"; n=$((n+1)); }
done
ls $L | wc -l | sed 's/^/libraries in compat dir: /'
# Orthanc also reads DCMTK 3.6.4's DICOM dictionary from /usr/share/libdcmtk14 (gone with the package from 24.04;
# the newer libdcmtk17 dictionary is rejected by the old parser): take it from the focal package
if [ ! -e /opt/compat-focal/share/libdcmtk14/dicom.dic ]; then
  mkdir -p /opt/compat-focal/debs /opt/compat-focal/share; cd /opt/compat-focal/debs
  f=libdcmtk14_3.6.4-2.1ubuntu0.2_amd64.deb
  [ -f $f ] || curl -fsSO http://archive.ubuntu.com/ubuntu/pool/universe/d/dcmtk/$f
  rm -rf x && dpkg-deb -x $f x && cp -a x/usr/share/libdcmtk14 /opt/compat-focal/share/ && rm -rf x
fi
[ -e /usr/share/libdcmtk14/dicom.dic ] || ln -sfn /opt/compat-focal/share/libdcmtk14 /usr/share/libdcmtk14
# The drop-ins disappeared during the 22.04 -> 24.04 upgrade: re-run this script after every hop
U=orthanc-build
# NETD's Ruby needs the shim only until it is rebuilt (rebuild-ruby.sh)
ldd /opt/netd/ruby/lib/ruby/*/x86_64-linux/openssl.so 2>/dev/null | grep -q "libssl.so.1.1" && U="$U netd-portal"
for u in $U; do
  mkdir -p /etc/systemd/system/$u.service.d
  printf '[Service]\n# Focal libraries during/after the Ubuntu upgrade (docs/OPERATIONS.md)\nEnvironment=LD_LIBRARY_PATH=%s\n' $L > /etc/systemd/system/$u.service.d/compat-focal.conf
done
systemctl daemon-reload
systemctl restart $U
sleep 15
systemctl is-active $U
