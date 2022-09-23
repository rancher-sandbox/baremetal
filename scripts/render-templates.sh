#! /bin/sh

set -o errexit
set -o nounset

######################################
# Privilege Escalation Configuration #
######################################
# This script tries to minimize the amount of commands it executes 
# with elevated privileges. When it does so, it will always execute 
# those commands as $PRIVILEGED_USER.
#
# $OPERATOR is assumed to be a user that SHOULD have access to manage
# deployments and such. It is NOT expected to be able to manipulate 
# the host filesystem outside of $PREFIX (defined above).

: ${PRIVILEGED_USER:="root"}


###########################
# Directory Configuration #
###########################
# Everything the script puts on disk somewhere should be here.
# $PREFIX will be made writable by $OPERATOR if it isn't already.

: ${PREFIX:="/opt/local"}

: ${BINARIES:="${PREFIX}/bin"}


################################
# Programs used by this script #
################################

# This ensures that everything we expect to be in $PATH, actually is.

${PROG_WHICH:="which"} \
    ${PROG_AWK:="awk"} \
    ${PROG_CHMOD:="chmod"} \
    ${PROG_CURL:="curl"} \
    ${PROG_GIT:="git"} \
    ${PROG_GREP:="grep"} \
    ${PROG_ID:="id"} \
    ${PROG_INSTALL:="install"} \
    ${PROG_SUDO:="sudo"} \
    ${PROG_TEST:="test"} \
    ${PROG_TR:="tr"} \
    ${PROG_WHOAMI:="whoami"} \
    ${PROG_WHICH} >/dev/null

: ${OPERATOR:=$(${PROG_WHOAMI})}
: ${OPERATOR_UID:=$(${PROG_ID} -u ${OPERATOR})}
: ${OPERATOR_GID:=$(${PROG_ID} -g ${OPERATOR})}

# Install gomplate if it doesn't exist
InstallGomplate() {
    : ${GOMPLATE_GITHUB_API_BASE_URL:="https://api.github.com/repos/hairyhenderson/gomplate"}

    # NOTE: make sure to use the release tag exactly as it appears
    # in https://github.com/hairyhenderson/gomplate/tags
    : ${GOMPLATE_RELEASE_TAG:="v3.11.2"}

    : ${GOMPLATE_DOWNLOAD_URL:=`${PROG_CURL} -s ${GOMPLATE_GITHUB_API_BASE_URL}/releases/tags/${GOMPLATE_RELEASE_TAG} | ${PROG_GREP} browser_download_url | ${PROG_GREP} 'linux-amd64"$' | ${PROG_AWK} '{print $2}' | ${PROG_TR} -d '"'`}

    if [ -z "${GOMPLATE_DOWNLOAD_URL}" ]
    then
        echo "ERROR: unable to lookup download URL for gomplate"
        exit 1
    fi

    # install pomplate per https://docs.gomplate.ca/installing/
    ${PROG_SUDO} --user "${PRIVILEGED_USER}" ${PROG_INSTALL} -d -m 0755 -o "${OPERATOR_UID}" -g "${OPERATOR_GID}" "${BINARIES}"
    ${PROG_SUDO} --user "${PRIVILEGED_USER}" ${PROG_CURL} -o ${BINARIES}/gomplate -sSL ${GOMPLATE_DOWNLOAD_URL}
    ${PROG_SUDO} --user "${PRIVILEGED_USER}" ${PROG_CHMOD} 755 ${BINARIES}/gomplate
}


if [ ! -e "${BINARIES}/gomplate" ]
then
    InstallGomplate
fi

: ${PROG_GOMPLATE:="gomplate"}


###########################
# Directory Configuration #
###########################

: ${ROOT:=$(${PROG_GIT} rev-parse --show-toplevel)}
: ${TEMPLATES_DIR:="${ROOT}/templates.d"}
: ${DEPLOY_DIR:="${ROOT}/deploy"}

################
# Main Program #
################

${PROG_TEST} "${DEBUG:-false}" = "false" || set -o xtrace

${PROG_GOMPLATE} \
    --verbose \
    --input-dir="${TEMPLATES_DIR}" \
    --output-map="${DEPLOY_DIR}/{{ .in | strings.TrimSuffix \".gomplate\" }}"
