
#######################################
#
# docker-install.sh
#
# require common.sh, prompt.sh, system.sh, docker-version.sh
#
#######################################

#######################################
# Installs requested docker version.
# Requires at least min docker version to proceed.
# Globals:
#   LSB_DIST
#   INIT_SYSTEM
#   AIRGAP
# Arguments:
#   Requested Docker Version
#   Minimum Docker Version
# Returns:
#   DID_INSTALL_DOCKER
#######################################
DID_INSTALL_DOCKER=0
installDocker() {
    _dockerGetBestVersion "$1"

    if ! commandExists "docker"; then
        _dockerRequireMinInstallableVersion "$2"
        _installDocker "$BEST_DOCKER_VERSION_RESULT" 1
        return
    fi

    getDockerVersion

    compareDockerVersions "$DOCKER_VERSION" "$2"
    if [ "$COMPARE_DOCKER_VERSIONS_RESULT" -eq "-1" ]; then
        _dockerRequireMinInstallableVersion "$2"
        _dockerForceUpgrade "$BEST_DOCKER_VERSION_RESULT"
    else
        compareDockerVersions "$DOCKER_VERSION" "$BEST_DOCKER_VERSION_RESULT"
        if [ "$COMPARE_DOCKER_VERSIONS_RESULT" -eq "-1" ]; then
            _dockerUpgrade "$BEST_DOCKER_VERSION_RESULT"
            if [ "$DID_INSTALL_DOCKER" -ne "1" ]; then
                _dockerProceedAnyway
            fi
        elif [ "$COMPARE_DOCKER_VERSIONS_RESULT" -eq "1" ]; then
            _dockerProceedAnyway "$BEST_DOCKER_VERSION_RESULT"
        fi
        # The system has the exact pinned version installed.
        # No need to run the Docker install script.
    fi
}

_installDocker() {
    if [ "$LSB_DIST" = "amzn" ]; then
        # Docker install script no longer supports Amazon Linux
        printf "${GREEN}Installing docker from Yum repository${NC}\n"
        # 1.12.6 and 17.03.2ce are available
        compareDockerVersions "17.0.0" "${1}"
        # if docker version is ce
        if [ "$COMPARE_DOCKER_VERSIONS_RESULT" -eq "-1" ]; then
            yum -y -q install docker-17.03.2ce
        else
            yum -y -q install docker-1.12.6
        fi
        service docker start || true
        DID_INSTALL_DOCKER=1
        return
    elif [ "$LSB_DIST" = "sles" ]; then
        # Docker install script no longer supports SUSE
        printf "${GREEN}Installing docker from Zypper repository${NC}\n"
        sudo zypper -n install "docker=${1}"
        service docker start || true
        DID_INSTALL_DOCKER=1
        return
    fi

    _docker_install_url="{{ replicated_install_url }}/docker-install.sh"
    printf "${GREEN}Installing docker from ${_docker_install_url}${NC}\n"
    getUrlCmd
    $URLGET_CMD "$_docker_install_url?docker_version=${1}&lsb_dist=${LSB_DIST}&dist_version=${DIST_VERSION_MAJOR}" > /tmp/docker_install.sh
    # When this script is piped into bash as stdin, apt-get will eat the remaining parts of this script,
    # preventing it from being executed.  So using /dev/null here to change stdin for the docker script.
    sh /tmp/docker_install.sh < /dev/null

    printf "${GREEN}External script is finished${NC}\n"

    # Need to manually start Docker in these cases
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        systemctl enable docker
        systemctl start docker
    elif [ "$LSB_DIST" = "centos" ]; then
        if [ "$(cat /etc/centos-release | cut -d" " -f3 | cut -d "." -f1)" = "6" ]; then
            service docker start
        fi
    fi

    # If the distribution is CentOS or RHEL and the filesystem is XFS, it is possible that docker has installed with overlay as the device driver
    # In that case we should change the storage driver to devicemapper, because while loopback-lvm is slow it is also more likely to work
    # set +e because df --output='fstype' doesn't exist on older versions of rhel and centos
    set +e
    if [ $2 -eq 1 ] && { [ "$LSB_DIST" = "centos" ] || [ "$LSB_DIST" = "rhel" ] ; } && { df --output='fstype' | grep -q -e '^xfs$' || grep -q -e ' xfs ' /etc/fstab ; } ; then
        # If distribution is centos or rhel and filesystem is XFS

        # Get kernel version (and extract major+minor version)
        kernelVersion="$(uname -r)"
        semverParse $kernelVersion

        if docker info | grep -q -e 'Storage Driver: overlay2\?' && { ! xfs_info / | grep -q -e 'ftype=1' || [ $major -lt 3 ] || { [ $major -eq 3 ] && [ $minor -lt 18 ]; }; }; then
            # If storage driver is overlay and (fstype!=1 OR kernel version less than 3.18)
            printf "${YELLOW}Changing docker storage driver to devicemapper as using overlay/overlay2 requires fstype=1 on xfs filesystems and requires kernel 3.18 or higher.\n"
            printf "It is recommended to configure devicemapper to use direct-lvm mode for production.${NC}\n"
            systemctl stop docker

            insertOrReplaceJsonParam /etc/docker/daemon.json storage-driver devicemapper

            systemctl start docker
        fi
    fi
    set -e

    DID_INSTALL_DOCKER=1
}

_dockerUpgrade() {
    if [ "$AIRGAP" != "1" ]; then
        printf "This installer will upgrade your current version of Docker (%s) to the recommended version: %s\n" "$DOCKER_VERSION" "$1"
        printf "Do you want to allow this? "
        if confirmY; then
            _installDocker "$1" 0
            return
        fi
    fi
}

_dockerForceUpgrade() {
    if [ "$AIRGAP" -eq "1" ]; then
        echo >&2 "Error: The installed version of Docker ($DOCKER_VERSION) may not be compatible with this installer."
        echo >&2 "Please manually upgrade your current version of Docker to the recommended version: $1"
        exit 1
    fi

    _dockerUpgrade "$1"
    if [ "$DID_INSTALL_DOCKER" -ne "1" ]; then
        printf "Please manually upgrade your current version of Docker to the recommended version: %s\n" "$1"
        exit 0
    fi
}

_dockerProceedAnyway() {
    printf "The installed version of Docker (%s) may not be compatible with this installer.\nThe recommended version is %s\n" "$DOCKER_VERSION" "$1"
    printf "Do you want to proceed anyway? "
    if ! confirmN; then
        exit 0
    fi
}

_dockerGetBestVersion() {
    BEST_DOCKER_VERSION_RESULT="$1"
    getMaxDockerVersion
    if [ -n "$MAX_DOCKER_VERSION_RESULT" ]; then
        compareDockerVersions "$BEST_DOCKER_VERSION_RESULT" "$MAX_DOCKER_VERSION_RESULT"
        if [ "$COMPARE_DOCKER_VERSIONS_RESULT" -eq "1" ]; then
            BEST_DOCKER_VERSION_RESULT="$MAX_DOCKER_VERSION_RESULT"
        fi
    fi
}

_dockerRequireMinInstallableVersion() {
    getMaxDockerVersion
    if [ -z "$MAX_DOCKER_VERSION_RESULT" ]; then
        return
    fi

    compareDockerVersions "$1" "$MAX_DOCKER_VERSION_RESULT"
    if [ "$COMPARE_DOCKER_VERSIONS_RESULT" -eq "1" ]; then
        echo >&2 "Error: This install script may not be compatible with this linux distribution."
        echo >&2 "We have detected a maximum docker version of $MAX_DOCKER_VERSION_RESULT while the required minimum version for this script is $1."
        exit 1
    fi
}
