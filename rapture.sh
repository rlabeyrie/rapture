#! /bin/bash

# Ugly hack to install debian packages in a local direcytory. Works only on
# debian-based systems. You can't remove the installed packages afterwards
# without actually deleting all the files by hand.
# Checks dependencies among regular system packages with dpkg, as well as
# packages installed with this script.
# Dependencies: curl, wget, date, dpkg, sed, ar, tar and a POSIX shell.
# Note: it outputs a lot of useless information.
# TODO: throw a bunch of sed commands on the post-install and configuration
# scripts in debian packages. Sometimes it's necessary.
# also TODO: a way to remember package files, and thus a way to uninstall
# packages.
# SHOULDHAVEDONE: use a more appropriate language (python). And do whatever it
# is that apt-get does, which is most probably not parse the debian web
# interface. Better off actually forking the real apt-get to allow an option to
# install elsewhere. But I don't think before I code.

# Where to look for debian packages. Currently parses the HTML main page of
# debian packages. Won't work with anything else.
DEBIAN_INDEX="http://packages.debian.org"
# Mirror to look for in the downloads list for each package.
DEBIAN_MIRROR="ftp.fr.debian.org"
# Only packages dedicated to this version of debian will be installed.
DEBIAN_VERSION="wheezy"
# Architecture of your system.
DEBIAN_ARCH="(amd64|all)"

# Where to install packages (data files will be directly deflated in this
# folder; this will create the usr/ directory and probably other system
# directories).
RAPTURE_INSTALL_DIR=~
# Where to download packages and keep track of dependencies.
RAPTURE_DIR=~/.rapture
# Where to write temporary files.
RAPTURE_TMP=/tmp/rapture

# You can now stop reading, below is the ugly part.

REPO=$DEBIAN_INDEX/$DEBIAN_VERSION
PACKAGE=$1
BUFFER=$RAPTURE_TMP/buffer

function is_installed {
    [ -x $RAPTURE_DIR/packages ] || touch $RAPTURE_DIR/packages
    if dpkg -s $1 >/dev/null 2>&1; then
        return 0
    elif grep -q $1 $RAPTURE_DIR/packages; then
        return 0
    else
        return 1
    fi
}

function download {
    curl $1 2>/dev/null
}

function get_data {
    download $REPO/$1 >$BUFFER
}

function get_package {
    mirror=$(<$BUFFER sed -rn 's@^.*(/'$DEBIAN_VERSION'/'$DEBIAN_ARCH'/.*download).*$@\1@p')
    download $DEBIAN_INDEX$mirror | sed -rn 's@^.*<a href="(http://'$DEBIAN_MIRROR'/.+deb)".*$@\1@p'
}

function get_dependencies {
    <$BUFFER sed -rn '/dep:/{N;s@^.*<a href="/'$DEBIAN_VERSION'/([^/]+)">\1</a>.*$@\1@p}'
}

function log {
    echo $(date +"%D %T") $@ >> $RAPTURE_DIR/log
}

function install {
    filename=$(echo $1 | grep -Eo '[^/]+deb$')
    target=$RAPTURE_DIR/debs/$filename
    echo "acquiring $filename" &&
        wget $1 -q -O $target &&
        (cd $RAPTURE_TMP && ar xf $target) &&
        echo "installing $filename" &&
        tar xf $RAPTURE_TMP/data.tar.gz -C $RAPTURE_INSTALL_DIR &&
        echo $filename >> $RAPTURE_DIR/packages
}

function process {
    if is_installed $1; then
        echo "already installed: $1"
    else
        echo "checking dependencies for package: $1"
        get_data $1
        pkg_url=$(get_package $1)
        if [ -z "$pkg_url" ]; then
            echo "nothing for this architecture: $DEBIAN_ARCH"
        else
            get_dependencies $1 | while read dep; do
                process $dep
            done
            install $pkg_url
        fi
    fi
}

[ -d $RAPTURE_TMP ] || mkdir -p $RAPTURE_TMP || echo "error: can't write to $RAPTURE_TMP" 1&>2

if is_installed $PACKAGE; then
    echo "package $PACKAGE already installed" >&2
    exit 1
fi

process $PACKAGE
