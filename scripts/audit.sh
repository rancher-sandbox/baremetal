#! /bin/sh

set -o errexit
set -o nounset

################################
# Programs used by this script #
################################
# This ensures that everything we expect to be in $PATH, actually is.

${PROG_WHICH:="which"} \
    ${PROG_CAT:="cat"} \
    ${PROG_DOCKER:="docker"} \
    ${PROG_FALSE:="false"} \
    ${PROG_GIT:="git"} \
    ${PROG_INSTALL:="install"} \
    ${PROG_JQ:="jq"} \
    ${PROG_PRINTF:="printf"} \
    ${PROG_TEST:="test"} \
    ${PROG_TRUE:="true"} \
    ${PROG_YQ:="yq"} \
    ${PROG_WHICH} >/dev/null

###########################
# Directory Configuration #
###########################

: ${ROOT:=$(${PROG_GIT} rev-parse --show-toplevel)}
: ${CONFIG_MAP_DIR:="${ROOT}/deploy/ironic/resource/ConfigMap"}
: ${EXTRACT_DIR:="${ROOT}/audit/ironic/resource/ConfigMap"}

#######################
# Image Configuration #
#######################

# : ${IMAGE_REF_FORMAT:="%s@sha256:%s"}
: ${IMAGE_REF_FORMAT:="%s:%s"}

: ${IRONIC_IMAGE:="quay.io/metal3-io/ironic"}
: ${IRONIC_IMAGE_REF_FORMAT:="${IMAGE_REF_FORMAT}"}
# : ${IRONIC_IMAGE_REF:="d1ab8429de7c09f4278ed7d83322123c13efa46da258bf59b0ebd41d329d82de"}
: ${IRONIC_IMAGE_REF:="capm3-v1.1.2"}

: ${IRONIC_IPA_DOWNLOADER_IMAGE:="quay.io/metal3-io/ironic-ipa-downloader"}
# : ${IRONIC_IPA_DOWNLOADER_IMAGE_REF_FORMAT:="${IMAGE_REF_FORMAT}"}
: ${IRONIC_IPA_DOWNLOADER_IMAGE_REF_FORMAT:="%s@sha256:%s"}
: ${IRONIC_IPA_DOWNLOADER_IMAGE_REF:="ee665aa486402e2084eeed4c42c69bab6f56de550e52978af1b73cb703818995"}

####################
# Helper Functions #
####################

AuditRef()
{
    case ${1} in
        ironic) ${PROG_PRINTF} "%s@%s" "${IRONIC_IMAGE}" "${IRONIC_IMAGE_REF}" ;;
        ironic-ipa-downloader) ${PROG_PRINTF} "%s@%s" "${IRONIC_IPA_DOWNLOADER_IMAGE}" "${IRONIC_IPA_DOWNLOADER_IMAGE_REF}" ;;
        *) ${PROG_FALSE} ;;
    esac
}

Image()
{
    case ${1} in
        ironic) ${PROG_PRINTF} "${IRONIC_IMAGE_REF_FORMAT}" "${IRONIC_IMAGE}" "${IRONIC_IMAGE_REF}" ;;
        ironic-ipa-downloader) ${PROG_PRINTF} "${IRONIC_IPA_DOWNLOADER_IMAGE_REF_FORMAT}" "${IRONIC_IPA_DOWNLOADER_IMAGE}" "${IRONIC_IPA_DOWNLOADER_IMAGE_REF}" ;;
        *) ${PROG_FALSE} ;;
    esac
}

Targets()
{
    ${PROG_CAT} "${CONFIG_MAP_DIR}/${1}/kustomization.yaml" \
        | ${PROG_YQ} . --output-format=json \
        | ${PROG_JQ} -r '.configMapGenerator[].files[]'
}

Prepare()
{
    ${PROG_INSTALL} -d "${EXTRACT_DIR}/$(AuditRef ${1})"
    Targets "${1}" > "${EXTRACT_DIR}/$(AuditRef ${1}).targets"
}

Pull()
{
    ${PROG_DOCKER} pull $(Image "${1}")
}

Extract()
{
    Prepare "${1}"
    ${PROG_DOCKER} run \
        --rm \
        --volume "${EXTRACT_DIR}/$(AuditRef ${1}).targets:/mnt/extract.targets:ro" \
        --volume "${EXTRACT_DIR}/$(AuditRef ${1}):/mnt/extract:rw" \
        --entrypoint /usr/bin/sh \
        $(Image "${1}") \
        -c "cat /mnt/extract.targets | xargs --replace=@ -- install --verbose -D /@ /mnt/extract/@"
}

Compare()
{
    ${PROG_GIT} diff \
    --no-index \
    --ignore-all-space \
    "${EXTRACT_DIR}/$(AuditRef ${1})" \
    "${CONFIG_MAP_DIR}/${1}"
}

Default()
{
    Extract ironic
    Extract ironic-ipa-downloader
    Compare ironic || ${PROG_TRUE}
    Compare ironic-ipa-downloader || ${PROG_TRUE}
}

################
# Main Program #
################

${PROG_TEST} "${DEBUG:-false}" = "false" || set -o xtrace

eval "${@:-Default}"
