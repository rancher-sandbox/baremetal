#! /bin/sh

set -o errexit
set -o nounset

##########################
# Required Configuration #
##########################

: ${REDFISH_HOST}
: ${REDFISH_USERNAME}
: ${REDFISH_PASSWORD}
: ${VIRTUAL_MEDIA_IMAGE_URL}

###########################
# Directory Configuration #
###########################

: ${PREFIX:="/opt/local"}
: ${SESSIONS_DIR:="${PREFIX}/redfish.sessions"}

################################
# Programs used by this script #
################################
# This ensures that everything we expect to be in $PATH, actually is.

${PROG_WHICH:="which"} \
    ${PROG_AWK:="awk"} \
    ${PROG_CURL:="curl"} \
    ${PROG_DATE:="date"} \
    ${PROG_ENVSUBST:="envsubst"} \
    ${PROG_FALSE:="false"} \
    ${PROG_INSTALL:="install"} \
    ${PROG_JQ:="jq"} \
    ${PROG_RM:="rm"} \
    ${PROG_TEST:="test"} \
    ${PROG_TR:="tr"} \
    ${PROG_TRUE:="true"} \
    ${PROG_WHICH} >/dev/null

##########################
# Optional Configuration #
##########################

: ${BOOT_MODE:="LegacyBios"}
: ${RESET_TYPE:="PushPowerButton"}
: ${VIRTUAL_MEDIA_TYPE:="CD"}

: ${INSECURE:="false"}
: ${SESSION_HEADERS:="${SESSIONS_DIR}/${REDFISH_HOST##https://}.headers"}
: ${SESSION_INFO:="${SESSIONS_DIR}/${REDFISH_HOST##https://}.json"}
: ${API_DISCOVERY:="false"}

: ${CURL_VERBOSITY_OPTIONS:="--silent"}

#################
# API Discovery #
#################

CallAPI()
{
    uri="${1}"
    shift 1
    ${PROG_CURL} "${REDFISH_HOST}/${uri#/}" \
        --fail \
        "${CURL_VERBOSITY_OPTIONS}" \
        --header "Content-Type: application/json;charset=utf-8" \
        --header "OData-Version: 4.0" \
        "${@:-}"
}

QueryJSON()
{
    ${PROG_JQ} -e -r "${@:-.}"
}

: ${REDFISH_API:="/redfish/"}

case "${API_DISCOVERY}" in
    false)
        : ${V1_API:="/redfish/v1/"}
        : ${MANAGERS_API:="/redfish/v1/Managers/"}
        : ${SESSION_SERVICE:="/redfish/v1/SessionService/"}
        : ${SESSIONS_API:="/redfish/v1/SessionService/Sessions/"}
        : ${SYSTEMS_API:="/redfish/v1/Systems/"}
        ;;
    *)
        : ${V1_API:=$(CallAPI "${REDFISH_API}" | QueryJSON ".v1")}
        : ${MANAGERS_API:=$(CallAPI "${V1_API}" | QueryJSON '.Managers["@odata.id"]')}
        : ${SESSION_SERVICE:=$(CallAPI "${V1_API}" | QueryJSON '.SessionService["@odata.id"]')}
        : ${SESSIONS_API:=$(CallAPI "${SESSION_SERVICE}" | QueryJSON '.Sessions["@odata.id"]')}
        : ${SYSTEMS_API:=$(CallAPI "${V1_API}" | QueryJSON '.Systems["@odata.id"]')}
        ;;
esac

: ${VIRTUAL_MEDIA:="/redfish/v1/Managers/1/VirtualMedia/"}

####################
# Helper Functions #
####################

EmptyObject()
{
    ${PROG_JQ} '.' <<EOF
{}
EOF
}

ParseDateTime()
{
    ${PROG_DATE} --date="${1}" +%s
}

Now()
{
    ${PROG_DATE} +%s
}

CanUseSessions() {
    CallAPI "${SESSION_SERVICE}" \
        | QueryJSON '.Status | [.State, .Health] | @tsv' \
        | ${PROG_AWK} '
            BEGIN { status = 1 }
            ($1 == "Enabled") && ($2 == "OK") { status = 0 }
            END { exit status }'
}

CallAuthenticatedAPI()
{
    uri="${1}"
    shift 1
    CallAPI "${uri}" \
        --header "X-Auth-Token: ${AUTH_TOKEN:=$(AuthToken)}" \
        "${@:-}"
}

AuthPayload()
{
    EmptyObject | QueryJSON -c ". \
        | .UserName=\"${REDFISH_USERNAME}\" \
        | .Password=\"${REDFISH_PASSWORD}\" \
    "
}

Login()
{
    CallAPI "${SESSIONS_API}" \
        --request POST \
        --data "$(AuthPayload)" \
        --output /dev/null \
        --dump-header "${SESSION_HEADERS}"
}

LoginHeaders()
{
    ${PROG_TEST} -f "${SESSION_HEADERS}" \
        || Login
    ${PROG_AWK} '{ print }' "${SESSION_HEADERS}"
}

AuthToken()
{
    LoginHeaders \
        | ${PROG_AWK} -F ": " '\
            BEGIN { status = 1 }
            $1 == "x-auth-token" { print $2; status = 0 }
            END { exit status }' \
        | ${PROG_TR} -d "[[:space:]]"
}

CurrentSession()
{
    LoginHeaders \
        | ${PROG_AWK} -F ": " '\
            BEGIN { status = 1 }
            $1 == "location" { sub("^https://[^/]+/","/",$2); print $2; status = 0 }
            END { exit status }' \
        | ${PROG_TR} -d "[[:space:]]"
}

Session()
{
    ${PROG_TEST} -f "${SESSION_INFO}" \
        || CallAuthenticatedAPI "$(CurrentSession)" \
            --output "${SESSION_INFO}"
    ${PROG_AWK} '{ print }' "${SESSION_INFO}"
}

SessionExpiry()
{
    ParseDateTime "$(Session | QueryJSON '.Oem.Hp.UserExpires')"
}

Logout()
{
    ${PROG_TEST} -f "${SESSION_HEADERS}" \
        && CallAuthenticatedAPI "$(CurrentSession)" \
            --request DELETE
}

SessionIsActive()
{
    ${PROG_TRUE} \
        && ${PROG_TEST} -f "${SESSION_HEADERS}" \
        && ${PROG_TEST} -f "${SESSION_INFO}" \
        && ${PROG_TEST} "$(Now)" -lt "$(SessionExpiry)"
}

CleanupSession()
{
    SessionIsActive \
        && Logout
    ${PROG_RM} -f "${SESSION_HEADERS}"
    ${PROG_RM} -f "${SESSION_INFO}"
}

##################################
# Virtual Media Helper Functions #
##################################

VirtualMediaMembers()
{
    CallAuthenticatedAPI "${VIRTUAL_MEDIA}" \
        | QueryJSON '.Members[] | .["@odata.id"]'
}

VirtualMediaMember()
{
    for media in $(VirtualMediaMembers)
    do CallAuthenticatedAPI "${media}" || ${PROG_TRUE}
    done \
        | QueryJSON ". | select(.MediaTypes[] | contains(\"${VIRTUAL_MEDIA_TYPE}\")) | .[\"@odata.id\"]"
}

EjectVirtualMediaTarget()
{
    CallAuthenticatedAPI $(VirtualMediaWithType "DVD") \
        | QueryJSON '.Oem.Hp.Actions["#HpiLOVirtualMedia.EjectVirtualMedia"].target'
}

InsertVirtualMediaTarget()
{
    CallAuthenticatedAPI $(VirtualMediaWithType "DVD") \
        | QueryJSON '.Oem.Hp.Actions["#HpiLOVirtualMedia.InsertVirtualMedia"].target'
}

InsertVirtualMediaPayload()
{
    EmptyObject | QueryJSON -c ". \
        | .Image=\"${VIRTUAL_MEDIA_IMAGE_URL}\" \
    "
}

VirtualMedia()
{
    CallAuthenticatedAPI "$(VirtualMediaMember)"
}

VirtualMediaIsInserted()
{
    ${PROG_TEST} "true" = "$(VirtualMedia | QueryJSON '.Inserted')"
}

InsertVirtualMedia()
{
    CallAuthenticatedAPI "$(InsertVirtualMediaTarget)" \
        --request POST \
        --data "$(InsertVirtualMediaPayload)"
}

EjectVirtualMedia()
{
    CallAuthenticatedAPI "$(EjectVirtualMediaTarget)" \
        --request POST \
        --data "{}"
}

##############################
# Boot Mode Helper Functions #
##############################

SystemTarget()
{
    CallAuthenticatedAPI "${SYSTEMS_API}" \
        | QueryJSON '.Members[0] | .["@odata.id"]'
}

System()
{
    CallAuthenticatedAPI "$(SystemTarget)"
}

ResetTarget()
{
    System \
        | QueryJSON ".Actions[\"#ComputerSystem.Reset\"] \
            | select(.[\"ResetType@Redfish.AllowableValues\"][] | contains(\"${RESET_TYPE}\")) \
            | .target"
}

ResetPayload()
{
    EmptyObject | QueryJSON -c ".
        | .ResetType=\"${RESET_TYPE}\"
    "
}

ResetSystem()
{
    CallAuthenticatedAPI "$(ResetTarget)" \
        --request POST \
        --data "$(ResetPayload)"
}

BiosTarget()
{
    System \
        | QueryJSON '.Oem.Hp.Links.BIOS["@odata.id"]'
}

BiosSettingsTarget()
{
    CallAuthenticatedAPI "$(BiosTarget)" \
        | QueryJSON '.links.Settings.href'
}

BiosSettings()
{
    CallAuthenticatedAPI "$(BiosSettingsTarget)"
}

BootMode()
{
    CallAuthenticatedAPI "$(BiosTarget)" \
        | QueryJSON '.BootMode'
}

BootModePayload()
{
    EmptyObject | QueryJSON -c ". \
        | .BootMode=\"${BOOT_MODE}\" \
    "
}

SetBootMode()
{
    CallAuthenticatedAPI "$(BiosSettingsTarget)" \
        --request PATCH \
        --data "$(BootModePayload)"
}

################
# Main Program #
################

Default()
{
    ${PROG_FALSE}
}

${PROG_TEST} -d "${SESSIONS_DIR}" || ${PROG_INSTALL} -d "${SESSIONS_DIR}"
${PROG_TEST} "${DEBUG:-false}" = "false" || set -o xtrace

eval "${@:-Default}"

