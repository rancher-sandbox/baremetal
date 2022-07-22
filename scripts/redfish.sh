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
    ${PROG_PRINTF:="printf"} \
    ${PROG_RM:="rm"} \
    ${PROG_SORT:="sort"} \
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

CallUnauthenticated()
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

CallAuthenticated()
{
    uri="${1}"
    shift 1
    CallUnauthenticated "${uri}" \
        --header "X-Auth-Token: ${AUTH_TOKEN:=$(AuthToken)}" \
        "${@:-}"
}

QueryJSON()
{
    ${PROG_JQ} -e -r "${@:-.}"
}

###########################
# API Discovery Functions #
###########################
# Realistically, a shell script probably isn't ideal for this. But,
# it'll have to do for now. Better to have something that works, than
# to have nothing at all, right?

URI()
{
    : ${REDFISH_BASE_URI:="/redfish/"}

    ${PROG_PRINTF} "%s" "${REDFISH_BASE_URI}"
}

API()
{
    CallUnauthenticated "$(URI)" "${@:-}"
}

V1URI()
{
    if ${PROG_TEST} "${API_DISCOVERY}" = "false"
    then : ${REDFISH_V1_URI:="/redfish/v1/"}
    else : ${REDFISH_V1_URI:=$(API | QueryJSON ".v1")}
    fi

    ${PROG_PRINTF} "%s" "${REDFISH_V1_URI}"
}

V1API()
{
    CallUnauthenticated "$(V1URI)" "${@:-}"
}

################################
# Systems API Helper Functions #
################################

SystemsURI()
{
    if ${PROG_TEST} "${API_DISCOVERY}" = "false"
    then : ${REDFISH_SYSTEMS_URI:="/redfish/v1/Systems/"}
    else : ${REDFISH_SYSTEMS_URI:=$(V1API | QueryJSON '.Systems["@odata.id"]')}
    fi

    ${PROG_PRINTF} "%s" "${REDFISH_SYSTEMS_URI}"
}

SystemsAPI()
{
    CallAuthenticated "$(SystemsURI)" "${@:-}"
}

SystemURI()
{
    if ${PROG_TEST} "${API_DISCOVERY}" = "false"
    then : ${REDFISH_SYSTEM_URI:="/redfish/v1/Systems/1/"}
    else : ${REDFISH_SYSTEM_URI:=$(SystemsAPI | QueryJSON '.Members[0] | .["@odata.id"]')}
    fi

    ${PROG_PRINTF} "%s" "${REDFISH_SYSTEM_URI}"
}

SystemAPI()
{
    CallAuthenticated "$(SystemURI)" "${@:-}"
}

SessionServiceURI()
{
    if ${PROG_TEST} "${API_DISCOVERY}" = "false"
    then : ${REDFISH_SESSION_SERVICE_URI:="/redfish/v1/SessionService/"}
    else : ${REDFISH_SESSION_SERVICE_URI:=$(V1API | QueryJSON '.SessionService["@odata.id"]')}
    fi

    ${PROG_PRINTF} "%s" "${REDFISH_SESSION_SERVICE_URI}"
}

SessionServiceAPI()
{
    CallUnauthenticated "$(SessionServiceURI)" "${@:-}"
}

SessionsURI()
{
    if ${PROG_TEST} "${API_DISCOVERY}" = "false"
    then : ${REDFISH_SESSIONS_URI:="/redfish/v1/SessionService/Sessions/"}
    else : ${REDFISH_SESSIONS_URI:=$(SessionServiceAPI | QueryJSON '.Sessions["@odata.id"]')}
    fi

    ${PROG_PRINTF} "%s" "${REDFISH_SESSIONS_URI}"
}

SessionsAPI()
{
    CallAuthenticated "$(SessionsURI)" "${@:-}"
}

CanUseSessions() {
    SessionServiceAPI \
        | QueryJSON '.Status | [.State, .Health] | @tsv' \
        | ${PROG_AWK} '
            BEGIN { status = 1 }
            ($1 == "Enabled") && ($2 == "OK") { status = 0 }
            END { exit status }'
}

# URI()
# {
#     if ${PROG_TEST} "${API_DISCOVERY}" = "false"
#     then :
#     else :
#     fi

#     ${PROG_PRINTF} "%s" "${REDFISH__URI}"
# }

############################
# Payload Helper Functions #
############################

EmptyObject()
{
    ${PROG_JQ} '.' <<EOF
{}
EOF
}

############################
# Session Helper Functions #
############################

AuthPayload()
{
    EmptyObject | QueryJSON -c ". \
        | .UserName=\"${REDFISH_USERNAME}\" \
        | .Password=\"${REDFISH_PASSWORD}\" \
    "
}

Login()
{
    CallUnauthenticated $(SessionsURI) \
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

CurrentSessionURI()
{
    LoginHeaders \
        | ${PROG_AWK} -F ": " '\
            BEGIN { status = 1 }
            $1 == "location" { sub("^https://[^/]+/","/",$2); print $2; status = 0 }
            END { exit status }' \
        | ${PROG_TR} -d "[[:space:]]"
}

SessionInfo()
{
    ${PROG_TEST} -f "${SESSION_INFO}" \
        || CallAuthenticated "$(CurrentSessionURI)" \
            --output "${SESSION_INFO}"
    ${PROG_AWK} '{ print }' "${SESSION_INFO}"
}

ParseDateTime()
{
    ${PROG_DATE} --date="${1}" +%s
}

Now()
{
    ${PROG_DATE} +%s
}

SessionExpiry()
{
    ParseDateTime "$(SessionInfo | QueryJSON '.Oem.Hp.UserExpires')"
}

Logout()
{
    ${PROG_TEST} -f "${SESSION_HEADERS}" \
        && CallAuthenticated "$(CurrentSessionURI)" \
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

#################################
# Managers API Helper Functions #
#################################

ManagersURI()
{
    if ${PROG_TEST} "${API_DISCOVERY}" = "false"
    then : ${REDFISH_MANAGERS_URI:="/redfish/v1/Managers/"}
    else : ${REDFISH_MANAGERS_URI:=$(V1API | QueryJSON '.Managers["@odata.id"]')}
    fi

    ${PROG_PRINTF} "%s" "${REDFISH_MANAGERS_URI}"
}

ManagersAPI()
{
    CallAuthenticated "$(ManagersURI)" "${@:-}"
}

ManagerURI()
{
    if ${PROG_TEST} "${API_DISCOVERY}" = "false"
    then : ${REDFISH_MANAGER_URI:="/redfish/v1/Managers/1/"}
    else : ${REDFISH_MANAGER_URI:=$(ManagersAPI | QueryJSON '.Members[0] | .["@odata.id"]')}
    fi

    ${PROG_PRINTF} "%s" "${REDFISH_MANAGER_URI}"
}

ManagerAPI()
{
    CallAuthenticated "$(ManagerURI)" "${@:-}"
}

##################################
# Virtual Media Helper Functions #
##################################

VirtualMediaManagerURI()
{
    if ${PROG_TEST} "${API_DISCOVERY}" = "false"
    then : ${REDFISH_VIRTUAL_MEDIA_MANAGER_URI:="/redfish/v1/Managers/1/VirtualMedia/"}
    else : ${REDFISH_VIRTUAL_MEDIA_MANAGER_URI:=$(ManagerAPI | QueryJSON '.VirtualMedia["@odata.id"]')}
    fi

    ${PROG_PRINTF} "%s" "${REDFISH_VIRTUAL_MEDIA_MANAGER_URI}"
}

VirtualMediaManagerAPI()
{
    CallAuthenticated "$(VirtualMediaManagerURI)"
}

VirtualMediaMembersURIs()
{
        
    if ${PROG_TEST} "${API_DISCOVERY}" = "false"
    then : ${REDFISH_VIRTUAL_MEDIA_MEMBERS_URI:="/redfish/v1/Managers/1/VirtualMedia/2/"}
    else : ${REDFISH_VIRTUAL_MEDIA_MEMBERS_URI:=$(VirtualMediaManagerAPI | QueryJSON '.Members[] | .["@odata.id"]')}
    fi

    ${PROG_PRINTF} "%s" "${REDFISH_VIRTUAL_MEDIA_MEMBERS_URI}"
}

VirtualMediaMembersAPI()
{
    for member in $(VirtualMediaMembersURIs)
    do CallAuthenticated "${member}" || ${PROG_TRUE}
    done
}

FindVirtualMediaMember()
{
    VirtualMediaMembersAPI \
        | QueryJSON ". \
            | select(.MediaTypes[] | contains(\"${1:-${VIRTUAL_MEDIA_TYPE}}\")) \
            | .[\"@odata.id\"]
        "
}

VirtualMediaMemberURI()
{
    if ${PROG_TEST} "${API_DISCOVERY}" = "false"
    then : ${REDFISH_VIRTUAL_MEDIA_MEMBER_URI:="/redfish/v1/Managers/1/VirtualMedia/2/"}
    else : ${REDFISH_VIRTUAL_MEDIA_MEMBER_URI:=$(FindVirtualMediaMember)}
    fi

    ${PROG_PRINTF} "%s" "${REDFISH_VIRTUAL_MEDIA_MEMBER_URI}"
}

VirtualMediaMemberAPI()
{
    CallAuthenticated "$(VirtualMediaMemberURI)" "${@:-}"
}

InsertVirtualMediaURI()
{
    if ${PROG_TEST} "${API_DISCOVERY}" = "false"
    then : ${REDFISH_INSERT_VIRTUAL_MEDIA_URI:="/redfish/v1/Managers/1/VirtualMedia/2/Actions/Oem/Hp/HpiLOVirtualMedia.InsertVirtualMedia/"}
    else : ${REDFISH_INSERT_VIRTUAL_MEDIA_URI:=$(VirtualMediaMemberAPI | QueryJSON '.Oem.Hp.Actions["#HpiLOVirtualMedia.InsertVirtualMedia"].target')}
    fi

    ${PROG_PRINTF} "%s" "${REDFISH_INSERT_VIRTUAL_MEDIA_URI}"
}

InsertVirtualMediaAPI()
{
    CallAuthenticated "$(InsertVirtualMediaURI)" "${@:-}"
}

InsertVirtualMediaPayload()
{
    EmptyObject | QueryJSON -c ". \
        | .Image=\"${VIRTUAL_MEDIA_IMAGE_URL}\" \
    "
}

InsertVirtualMedia()
{
    InsertVirtualMediaAPI \
        --request POST \
        --data "$(InsertVirtualMediaPayload)"
}

VirtualMediaIsInserted()
{
    ${PROG_TEST} "true" = "$(VirtualMediaMemberAPI | QueryJSON '.Inserted')"
}


EjectVirtualMediaURI()
{
    if ${PROG_TEST} "${API_DISCOVERY}" = "false"
    then : ${REDFISH_EJECT_VIRTUAL_MEDIA_URI:="/redfish/v1/Managers/1/VirtualMedia/2/Actions/Oem/Hp/HpiLOVirtualMedia.EjectVirtualMedia/"}
    else : ${REDFISH_EJECT_VIRTUAL_MEDIA_URI:=$(VirtualMediaMemberAPI | QueryJSON '.Oem.Hp.Actions["#HpiLOVirtualMedia.EjectVirtualMedia"].target')}
    fi

    ${PROG_PRINTF} "%s" "${REDFISH_EJECT_VIRTUAL_MEDIA_URI}"
}

EjectVirtualMediaAPI()
{
    CallAuthenticated "$(EjectVirtualMediaURI)" "${@:-}"
}

EjectVirtualMedia()
{
    EjectVirtualMediaAPI \
        --request POST \
        --data "$(EjectVirtualMediaPayload)"
}

EjectVirtualMediaPayload()
{
    EmptyObject
}

##############################
# Boot Mode Helper Functions #
##############################

BiosURI()
{
    if ${PROG_TEST} "${API_DISCOVERY}" = "false"
    then : ${REDFISH_BIOS_URI:="/redfish/v1/systems/1/bios/"}
    else : ${REDFISH_BIOS_URI:=$(SystemAPI | QueryJSON '.Oem.Hp.Links.BIOS["@odata.id"]')}
    fi

    ${PROG_PRINTF} "%s" "${REDFISH_BIOS_URI}"
}

BiosAPI()
{
    CallAuthenticated "$(BiosURI)" "${@:-}"
}

BiosSettingsURI()
{
    if ${PROG_TEST} "${API_DISCOVERY}" = "false"
    then : ${REST_BIOS_SETTINGS_URI:="/rest/v1/systems/1/bios/Settings"}
    else : ${REST_BIOS_SETTINGS_URI:=$(BiosAPI | QueryJSON '.links.Settings.href')}
    fi

    ${PROG_PRINTF} "%s" "${REST_BIOS_SETTINGS_URI}"
}

BiosSettingsAPI()
{
    CallAuthenticated "$(BiosSettingsURI)" "${@:-}"
}

BootMode()
{
    BiosAPI \
        | QueryJSON '.BootMode'
}

SecureBootURI()
{
    if ${PROG_TEST} "${API_DISCOVERY}" = "false"
    then : ${REDFISH_SECURE_BOOT_URI:="/redfish/v1/Systems/1/SecureBoot/"}
    else : ${REDFISH_SECURE_BOOT_URI:=$(SystemAPI | QueryJSON '.Oem.Hp.Links.SecureBoot["@odata.id"]')}
    fi

    ${PROG_PRINTF} "%s" "${REDFISH_SECURE_BOOT_URI}"
}

SecureBootAPI()
{
    CallAuthenticated "$(SecureBootURI)" "${@:-}"
}

SecureBootCurrentState()
{
    SecureBootAPI \
        | QueryJSON '.SecureBootCurrentState'
}

SecureBootEnabled()
{
    SecureBootAPI \
        | QueryJSON '.SecureBootEnable'
}

EnableSecureBootPayload()
{
    EmptyObject | QueryJSON ". \
        | .SecureBootEnable=true
    "
}

EnableSecureBoot()
{
    SecureBootAPI \
        --request POST \
        --data "$(EnableSecureBootPayload)"
}

BiosUefiClass()
{
    if ${PROG_TEST} "${BIOS_DISCOVERY:-false}" = "false"
    then : ${BIOS_UEFI_CLASS:="2"}
    else : ${BIOS_UEFI_CLASS:=$(SystemAPI | QueryJSON '.Oem.Hp.Bios.UefiClass//0')}
    fi

    ${PROG_PRINTF} "%s" "${BIOS_UEFI_CLASS}"
}

BootModesAvailable()
{
    case $(BiosUefiClass) in
        0) ${PROG_PRINTF} "%s\n" "LegacyBios" ;;
        2) ${PROG_PRINTF} "%s\n" "LegacyBios" "UEFI" ;;
        3) ${PROG_PRINTF} "%s\n" "UEFI" ;;
        *) ${PROG_FALSE} ;;
    esac
}

BootModePayload()
{
    case ${BOOT_MODE} in
        legacy|Legacy|LegacyBios) BootModePayloadLegacyBios ;;
        *) BootModePayloadUEFI ;;
    esac
}

BootModePayloadLegacyBios()
{
    EmptyObject | QueryJSON -c ". \
        | .BootMode=\"LegacyBios\" \
    "
}

BootModePayloadUEFI()
{
    EmptyObject | QueryJSON -c ". \
        | .BootMode=\"UEFI\" \
        | .UefiOptimizedBoot=\"Enabled\" \
    "
}

SetBootMode()
{
    BiosSettingsAPI \
        --request PATCH \
        --data "$(BootModePayload)"
}

#####################################
# Power Management Helper Functions #
#####################################

ResetTypes()
{
    SystemAPI \
        | QueryJSON ". \
            | .Actions[\"#ComputerSystem.Reset\"] \
            | .[\"ResetType@Redfish.AllowableValues\"][]
        "
}

ResetURI()
{
    SystemAPI \
        | QueryJSON ".Actions[\"#ComputerSystem.Reset\"] \
            | select(.[\"ResetType@Redfish.AllowableValues\"][] | contains(\"${RESET_TYPE}\")) \
            | .target"
}

ResetAPI()
{
    CallAuthenticated "$(ResetSystemURI)" "${@:-}"
}

ResetPayload()
{
    EmptyObject | QueryJSON -c ".
        | .ResetType=\"${RESET_TYPE}\"
    "
}

Reset()
{
    ResetAPI \
        --request POST \
        --data "$(ResetPayload)"
}

################
# Main Program #
################

Help()
{
    ${PROG_AWK} '$1 ~ /^[[:alnum:]]+[(][)]$/ { sub("()","",$1); print }' "${0}" \
        | ${PROG_SORT}
}

help() { Help; }

Default()
{
    Help
}

${PROG_TEST} -d "${SESSIONS_DIR}" || ${PROG_INSTALL} -d "${SESSIONS_DIR}"
${PROG_TEST} "${DEBUG:-false}" = "false" || set -o xtrace

eval "${@:-Default}"

