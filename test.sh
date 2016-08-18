#!/bin/bash


ALL_COMMANDS="exec run shell start stop bootstrap copy create expand export import mount"

if [ ! -f "autogen.sh" ]; then
    /bin/echo "ERROR: Run this from the singularity source root"
    exit 1
fi

if [ ! -f "libexec/functions" ]; then
    /bin/echo "ERROR: Could not find functions file"
    exit 1
fi


MESSAGELEVEL=3
STARTDIR=`pwd`
TEMPDIR=`mktemp -d /tmp/singularity-test.XXXXXX`
CONTAINER="container.img"
CONTAINERDIR="container_dir"
SINGULARITY_CACHEDIR="$TEMPDIR"
export SINGULARITY_CACHEDIR MESSAGELEVEL


/bin/echo "Gaining/checking sudo access..."
sudo true

if [ -z "$CLEAN_SHELL" ]; then
    /bin/echo "Building/Installing Singularity to temporary directory"
    /bin/echo "Reinvoking in a clean shell"
    sleep 1
    exec env -i CLEAN_SHELL=1 PATH="/bin:/usr/bin:/sbin:/usr/sbin" bash "$0" "$*"
fi

. ./libexec/functions

make maintainer-clean >/dev/null 2>&1
stest 0 ./autogen.sh
stest 0 ./configure --prefix="$TEMPDIR" --with-userns
stest 0 make
stest 0 sudo make install


PATH="$TEMPDIR/bin:/usr/local/bin:$PATH"
MESSAGELEVEL=5

/bin/echo
/bin/echo "SINGULARITY_TMPDIR=$SINGULARITY_CACHEDIR"
/bin/echo "PATH=$PATH"
/bin/echo

/bin/echo "Creating temp working space at: $TEMPDIR"
stest 0 mkdir -p "$TEMPDIR"
stest 0 pushd "$TEMPDIR"

/bin/echo
/bin/echo "Running base tests..."
/bin/echo

# Testing singularity internal commands
stest 0 singularity
stest 0 singularity --help
stest 0 singularity --version
for i in $ALL_COMMANDS; do
    echo
    echo "Testing command usage: '$i'"
    stest 0 singularity --help "$i"
    stest 0 singularity -h "$i"
    stest 0 singularity help "$i"
    stest 0 singularity $i help
    stest 0 singularity $i -h
    stest 0 singularity $i --help
done

/bin/echo
/bin/echo "Testing error on bad commands"

stest 1 singularity help bogus
stest 1 singularity bogus help

/bin/echo
/bin/echo "Building test container..."

stest 0 sudo singularity create -s 568 "$CONTAINER"
# We will need a setuid binary (ping) for the NO_NEW_PRIVS test below.
stest 0 sed -i "$STARTDIR/examples/centos.def" -e 's|#InstallPkgs yum vim-minimal|InstallPkgs iputils|'
stest 0 sudo singularity bootstrap "$CONTAINER" "$STARTDIR/examples/busybox.def"

/bin/echo
/bin/echo "Running container shell tests..."

stest 0 singularity shell "$CONTAINER" -c "true"
stest 1 singularity shell "$CONTAINER" -c "false"
stest 0 sh -c "echo true | singularity shell '$CONTAINER'"
stest 1 sh -c "echo false | singularity shell '$CONTAINER'"

/bin/echo
/bin/echo "Running container exec tests..."

stest 0 singularity exec "$CONTAINER" true
stest 0 singularity exec "$CONTAINER" /bin/true
stest 1 singularity exec "$CONTAINER" false
stest 1 singularity exec "$CONTAINER" /bin/false
stest 1 singularity exec "$CONTAINER" /blahh
stest 1 singularity exec "$CONTAINER" blahh
stest 0 sh -c "echo hi | singularity exec $CONTAINER grep hi"
stest 1 sh -c "echo bye | singularity exec $CONTAINER grep hi"

/bin/echo
/bin/echo "Running container run tests..."

# Before we have a runscript, it should invoke a shell
stest 0 singularity run "$CONTAINER" -c true
stest 1 singularity run "$CONTAINER" -c false
echo -ne "#!/bin/sh\n\neval \"\$@\"\n" > singularity
stest 0 chmod 0644 singularity
stest 0 sudo singularity copy "$CONTAINER" -a singularity /
stest 1 singularity run "$CONTAINER" true
stest 0 sudo singularity exec -w "$CONTAINER" chmod 0755 /singularity
stest 0 singularity run "$CONTAINER" true
stest 1 singularity run "$CONTAINER" false


/bin/echo
/bin/echo "Checking writableness..."

stest 0 sudo chown root.root "$CONTAINER"
stest 0 sudo chmod 0644 "$CONTAINER"
stest 0 sudo singularity shell -w "$CONTAINER" -c true
stest 0 sudo singularity exec -w "$CONTAINER" true
stest 0 sudo singularity run -w "$CONTAINER" true
stest 1 singularity shell -w "$CONTAINER" -c true
stest 1 singularity exec -w "$CONTAINER" true
stest 1 singularity run -w "$CONTAINER" true
stest 0 sudo chmod 0666 "$CONTAINER"
stest 0 sudo singularity shell -w "$CONTAINER" -c true
stest 0 sudo singularity exec -w "$CONTAINER" true
stest 0 sudo singularity run -w "$CONTAINER" true
stest 0 singularity shell -w "$CONTAINER" -c true
stest 0 singularity exec -w "$CONTAINER" true
stest 0 singularity run -w "$CONTAINER" true
stest 1 singularity exec "$CONTAINER" touch /writetest.fail
stest 0 sudo singularity exec "$CONTAINER" touch /writetest.fail #### This works thanks to the overlayfs now, maybe it should be conditional here?
stest 0 sudo singularity exec -w "$CONTAINER" touch /writetest.pass


/bin/echo
/bin/echo "Checking Bootstrap on existing container..."

stest 0 sudo singularity bootstrap "$CONTAINER"
stest 0 singularity exec "$CONTAINER" test -f /environment
stest 0 sudo singularity exec -w "$CONTAINER" rm /environment
stest 1 singularity exec "$CONTAINER" test -f /environment
stest 0 sudo singularity bootstrap "$CONTAINER"
stest 0 singularity exec "$CONTAINER" test -f /environment
stest 0 singularity exec "$CONTAINER" test -f /.shell
stest 0 singularity exec "$CONTAINER" test -f /.exec
stest 0 singularity exec "$CONTAINER" test -f /.run


/bin/echo
/bin/echo "Checking configuration file ownership..."

stest 0 singularity exec "$CONTAINER" true
stest 0 sudo chown `id -un` "$TEMPDIR/etc/singularity/singularity.conf"
stest 1 singularity exec "$CONTAINER" true
stest 0 sudo chown root.root "$TEMPDIR/etc/singularity/singularity.conf"
stest 0 singularity exec "$CONTAINER" true


/bin/echo
/bin/echo "Checking export/import..."

stest 0 sudo singularity export -f ${CONTAINERDIR}.tar "$CONTAINER"
stest 0 mkdir $CONTAINERDIR
stest 0 sudo tar -C $CONTAINERDIR -xvf ${CONTAINERDIR}.tar
stest 0 sudo chmod 0644 ${CONTAINERDIR}.tar
stest 0 sudo rm -f "$CONTAINER"
stest 0 sudo singularity create -s 568 "$CONTAINER"
stest 0 sh -c "cat ${CONTAINERDIR}.tar | sudo singularity import $CONTAINER"


/bin/echo
/bin/echo "Checking directory mode"
stest 0 singularity exec $CONTAINERDIR true
stest 1 singularity exec /tmp true
stest 1 singularity exec / true


/bin/echo
/bin/echo "Checking NO_NEW_PRIVS"
stest 1 singularity exec "$CONTAINER" ping localhost -c 1
stest 1 singularity exec $CONTAINERDIR ping localhost -c 1


/bin/echo
/bin/echo "Checking target UID mode"
stest 0 sh -c "sudo SINGULARITY_TARGET_GID=`id -g` SINGULARITY_TARGET_UID=`id -u` singularity exec $CONTAINER whoami | grep -q `id -un`"

 
#TODO: The following tests must be conditional based on host capabilities
/bin/echo
/bin/echo "Disabling setuid config flag"
stest 0 sudo sed -i $TEMPDIR/etc/singularity/singularity.conf -e 's|allow setuid = yes|allow setuid = no|'
stest 1 singularity exec "$CONTAINER" true

/bin/echo
/bin/echo "Checking unprivileged mode"
stest 0 sh -c "singularity exec $CONTAINERDIR whoami | grep -q `id -un`"
stest 1 sh -c "singularity exec $CONTAINER whoami"


/bin/echo
/bin/echo "Re-enabling setuid config flag"
stest 0 sudo sed -i $TEMPDIR/etc/singularity/singularity.conf -e 's|allow setuid = no|allow setuid = yes|'
stest 0 singularity exec "$CONTAINER" true


/bin/echo
/bin/echo "Checking unprivileged mode from environment"
stest 0 sh -c "SINGULARITY_NOSUID=1 singularity exec $CONTAINERDIR whoami | grep -q `id -un`"
stest 1 sh -c "SINGULARITY_NOSUID=1 singularity exec $CONTAINER whoami"



#/bin/echo
#/bin/echo "Checking scratch directory creation"
#mkdir -p /tmp/foo
#touch /tmp/foo/bar
#stest 0 sh -c "singularity exec $CONTAINER find /tmp/foo -type f | grep -q /tmp"
#stest 1 sh -c "singularity exec -S /tmp $CONTAINER find /tmp/foo -type f | grep -q /tmp"
#
# NOTICE: What is difference between scratch directory and user bind mount?
#
#/bin/echo
#/bin/echo "Testing user bind mounts"
#mkdir -p $TEMPDIR/foo/bar/baz/
#touch $TEMPDIR/foo/bar/baz/qux
#stest 0 singularity exec -B $TEMPDIR/foo,/var/lib/test/foo "$CONTAINER" test -f /var/lib/test/foo/bar/baz/qux
#stest 0 sh -c "SINGULARITY_FORCE_NOSUID=1 singularity exec -B $TEMPDIR/foo,/var/lib/test/foo $CONTAINERDIR test -f /var/lib/test/foo/bar/baz/qux"
#stest 0 singularity exec -B $TEMPDIR/foo,/var/lib/test/foo "$CONTAINER" test -d /var/lib/test/
## This is a quirk of the bind mount code that can only be fixed with overlayfs-based binds.
#stest 1 singularity exec -B $TEMPDIR/foo,/var/lib/test/foo "$CONTAINER" test -d /var/lib/alternatives/
#stest 0 singularity exec "$CONTAINER" test -d /var/lib/alternatives/


/bin/echo
/bin/echo "Cleaning up"

stest 0 popd
stest 0 sudo rm -rf "$TEMPDIR"
stest 0 make maintainer-clean

# Need to refix for flawfinder happiness
#/bin/echo
#if `which flawfinder > /dev/null`; then
#    /bin/echo "Testing source code with flawfinder"
#    stest 0 sh -c "flawfinder . | tee /dev/stderr | grep -q -e 'No hits found'"
#else
#    /bin/echo "WARNING: flawfinder is not found, test skipped"
#fi

/bin/echo
/bin/echo "Done. All tests completed successfully"
/bin/echo

