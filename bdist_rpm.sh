#!/bin/bash


# Clean
rm -Rf BUILD SOURCES SPECS RPMS BUILDROOT
mkdir -p BUILD SOURCES SPECS RPMS BUILDROOT

./autogen.sh
./configure --prefix=/usr --sysconfdir=/etc
make dist


VERSION=$(grep "Version:.*[0-9]" singularity.spec | tr -s " " |  awk '{print $2;}')
GITTAG=$(git log --format=%ct.%h -1)

# Copy required files
cp "singularity-${VERSION}.tar.gz" "SOURCES"
cp singularity.spec "SPECS"


rpmbuild --define "gittag ${GITTAG}" --define "_topdir $PWD" -ba SPECS/singularity.spec

# Clean
rm -Rf "singularity-${VERSION}.tar.gz"
