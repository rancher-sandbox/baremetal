#! /bin/sh

set -o errexit
set -o nounset

################################
# Programs used by this script #
################################
# This ensures that everything we expect to be in $PATH, actually is.

${PROG_WHICH:="which"} \
    ${PROG_GIT:="git"} \
    ${PROG_GOMPLATE:="gomplate"} \
    ${PROG_TEST:="test"} \
    ${PROG_WHICH} >/dev/null

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
