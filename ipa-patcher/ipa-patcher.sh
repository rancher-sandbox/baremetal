#! /bin/sh

set -o errexit
set -o nounset

################################
# Programs used by this script #
################################
# This ensures that everything we expect to be in $PATH, actually is.

${PROG_WHICH:="which"} \
    ${PROG_BSDCPIO:="bsdcpio"} \
    ${PROG_BSDTAR:="bsdtar"} \
    ${PROG_CURL:="curl"} \
    ${PROG_EGREP:="egrep"} \
    ${PROG_FALSE:="false"} \
    ${PROG_FILE:="file"} \
    ${PROG_FIND:="find"} \
    ${PROG_GZIP:="gzip"} \
    ${PROG_INSTALL:="install"} \
    ${PROG_MD5SUM:="md5sum"} \
    ${PROG_MV:="mv"} \
    ${PROG_RM:="rm"} \
    ${PROG_SED:="sed"} \
    ${PROG_TEST:="test"} \
    ${PROG_TRUE:="true"} \
    ${PROG_WHICH} >/dev/null

###########################
# Directory Configuration #
###########################

: ${INPUTS:="/mnt/inputs"}
: ${WORK:="/tmp"}
: ${OUTPUTS:="/mnt/outputs"}

######################
# Component Versions #
######################
# The goal of this script is to create a reproducible process, 
# not to install the latest versions of everything. To that end, all 
# components versions are defined here.

: ${VERSION:="6fdbde2576bd48e3e9624ac5a1dd61f8"}

###########################
# Mirroring Configuration #
###########################
# This script pulls things from The Internet (TM). If that's not 
# something you want, this section should contain all remote URLs that 
# are used anywhere in this script. Additional URLs may be derived from 
# these, so consider them more as base URLs. Actually mirroring the 
# appropriate components is out of scope for this script.

: ${UPSTREAM:="https://images.rdoproject.org/centos8/master/rdo_trunk"}

##################################################
# Downloads and Archive Extraction Configuration #
##################################################
# This is all stuff for dealing with downloaded archives/scripts, 
# and how  to extract the things we need from from them. You probably
# won't need to change anything here, but releases may break things.
# When that happens, this is probably what needs to be fixed.

: ${TARBALL:="ironic-python-agent.tar"}
: ${CHECKSUM:="ironic-python-agent.tar.md5"}
: ${INITRAMFS:="ironic-python-agent.initramfs"}
: ${KERNEL:="ironic-python-agent.kernel"}
: ${SERVICE:="usr/lib/systemd/system/openstack-ironic-python-agent.service"}

#########################
# Special Configuration #
#########################

# Setting this to anything other than false will cause the inputs to be
# purged if they exist, forcing them to redownload.
: ${FORCE:="false"}

Prepare()
{
    ${PROG_TEST} -d "${INPUTS}"      || ${PROG_INSTALL} -d "${INPUTS}"
    ${PROG_TEST} -d "${OUTPUTS}"     || ${PROG_INSTALL} -d "${OUTPUTS}"
    ${PROG_TEST} -d "${WORK}/rootfs" || ${PROG_INSTALL} -d "${WORK}/rootfs"

    ${PROG_TEST} "${FORCE}" = "false" \
        || ${PROG_RM} -f \
            "${INPUTS}/${INITRAMFS}" \
            "${INPUTS}/${KERNEL}" \
            "${INPUTS}/${TARBALL}"
}

Download()
{
    ${PROG_TEST} -f "${INPUTS}/${TARBALL}" \
        || ${PROG_CURL} \
            --location \
            --output "${INPUTS}/${TARBALL}" \
            "${UPSTREAM}/${VERSION}/${TARBALL}"
}

Extract()
{
    ${PROG_TEST} -f "${WORK}/${KERNEL}" \
        || ${PROG_BSDTAR} \
            --extract \
            --file "${INPUTS}/${TARBALL}" \
            --directory "${WORK}" \
            "${KERNEL}"
    ${PROG_TEST} -f "${WORK}/${INITRAMFS}" \
        || ${PROG_BSDTAR} \
            --extract \
            --file "${INPUTS}/${TARBALL}" \
            --directory "${WORK}" \
            "${INITRAMFS}"

    case $(${PROG_FILE} --mime-type --brief "${WORK}/${INITRAMFS}") in
        application/gzip)
            ${PROG_MV} "${WORK}/${INITRAMFS}" "${WORK}/${INITRAMFS}.gz"
            ${PROG_GZIP} -d "${WORK}/${INITRAMFS}.gz"
            ;;
        application/x-cpio)
            ${PROG_TRUE}
            ;;
        *)
            ${PROG_FALSE}
            ;;
    esac
}

PatchServiceUnit()
{
    ${PROG_BSDTAR} \
        --extract \
        --file "${WORK}/${INITRAMFS}" \
        --to-stdout \
        "${SERVICE}" \
        | ${PROG_EGREP} -q '^StandardOutput=inherit$' \
        || {
            cd "${WORK}/rootfs"
            ${PROG_BSDCPIO} \
                --extract \
                --file "${WORK}/${INITRAMFS}" \
                --make-directories
            ${PROG_SED} -E -i \
                -e 's/^(StandardOutput)=.+$/\1=inherit/' \
                "${SERVICE}"
            ${PROG_FIND} . \
                | ${PROG_BSDCPIO} \
                    --create \
                    --file "${WORK}/${INITRAMFS}" \
                    --format newc 
        }
}

CreateArchive()
{
    ${PROG_BSDTAR} \
        --create \
        --file "${OUTPUTS}/${TARBALL}" \
        --directory "${WORK}" \
        "${INITRAMFS}" \
        "${KERNEL}"
}

UpdateChecksum()
{
    cd "${OUTPUTS}"
    ${PROG_MD5SUM} "${TARBALL}" > "${CHECKSUM}"
}

################
# Main Program #
################

Default()
{
    Prepare
    Download
    Extract
    PatchServiceUnit
    CreateArchive
    UpdateChecksum
}

${PROG_TEST} "${DEBUG:-false}" = "false" || set -o xtrace

eval "${@:-Default}"
