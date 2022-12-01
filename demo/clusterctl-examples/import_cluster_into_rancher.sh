#!/bin/bash

USAGE="${0}: --cluster-name <workload cluster name> --rancher-endpoint <Rancher API endpoint> --rancher-username <Rancher username> --rancher-password <Rancher password>

Where:

  <workload cluster name>: name of the workload cluster to be imported
  <Rancher API endpoint>: Rancher API endpoint URL. i.e. http://rancher.foo.io
  <Rancher username>: Rancher (admin) username to authenticate to Rancher
  <Rancher password>: password for the Rancher user.
                      However you may use the environment variable
		      RANCHER_PASSWORD to convey the Rancher user password
		      instead.
"

while [[ $# -gt 0 ]] ; do
    case $1 in
        --cluster-name)
	    CLUSTER_NAME="$2"
	    shift
	    shift
	    ;;
	--rancher-endpoint)
	    RANCHER_ENDPOINT="$2"
	    shift
	    shift
	    ;;
	--rancher-username)
            RANCHER_USERNAME="$2"
	    shift
	    shift
	    ;;
	--rancher-password)
            RANCHER_PASSWORD="$2"
	    shift
	    shift
	    ;;
	*)
            echo "$USAGE"
	    exit 1
    esac
done

if [[ -z "$CLUSTER_NAME" || -z "$RANCHER_USERNAME" || -z "$RANCHER_PASSWORD" || -z "$RANCHER_ENDPOINT" ]] ; then
    echo "$USAGE"
    exit 1
fi

WORKLOAD_CLUSTER_KUBECONF_FILE=$(mktemp /tmp/${CLUSTER_NAME}.kubeconf.XXXXXX)

function cleanup_files()
{
    if [[ -f $WORKLOAD_CLUSTER_KUBECONF_FILE ]] ; then
        rm -f $WORKLOAD_CLUSTER_KUBECONF_FILE
    fi
}

function cleanup_and_error_out()
{
    cleanup_files
    exit 1
}

# check to see if we have all the required tools
for CLI in clusterctl curl jq kubectl mktemp
do
    which $CLI > /dev/null
    if [[ $? -ne 0 ]] ; then
        echo 'ERROR: ${CLI} not found. Please install it first.'
	exit 1
    fi
done

#################################
# Get Rancher bearer auth token #
#################################

RANCHER_AUTH_REQUEST_PAYLOAD="
{
    \"username\": \"${RANCHER_USERNAME}\",
    \"password\": \"${RANCHER_PASSWORD}\",
    \"responseType\": \"json\"
}
"
RESP=$(curl -XPOST -s -k -d "${RANCHER_AUTH_REQUEST_PAYLOAD}" -H "Content-Type: application/json" ${RANCHER_ENDPOINT}/v3-public/localProviders/local?action=login)
if [[ ! "$RESP" == *"token"* ]] ; then
    echo "
    ERROR: failed to authenticate to Rancher to obtain a bearer token. Please make sure the
    Rancher user and password are correctly specified. ${RESP}
    "
    exit 1
fi
RANCHER_AUTH_TOKEN=$(echo "$RESP" | jq -r .token)
if [[ ! "$RANCHER_AUTH_TOKEN" == *"token"* ]] ; then
    echo "ERROR: failed to parse auth token from ${RESP}"
    exit 1
fi


################################################
# Download kubeconfig for the workload cluster #
################################################

clusterctl get kubeconfig $CLUSTER_NAME > $WORKLOAD_CLUSTER_KUBECONF_FILE
if [[ $? -ne 0 ]] ; then
    echo "
    ERROR: unable to get kubeconfig for workload cluster ${CLUSTER_NAME}.
    Please make sure clusterctl is properly configured and that the workload
    cluster name is correct.
    "
    rm $CLUSTER_KUBECONF
    exit 1
fi


########################################
# Create the import cluster in Rancher #
########################################

RANCHER_PROVISIONING_CLUSTER_REQUEST_PAYLOAD=$(cat << EOF
{
    "type": "provisioning.cattle.io.cluster",
    "metadata": {
        "namespace": "fleet-default",
        "annotations": {
            "field.cattle.io/description": "workload cluster managed by CAPI"
        },
        "name": "${CLUSTER_NAME}"
    },
    "spec": {}
}
EOF
)
RESP=$(curl -XPOST -s -k -d "${RANCHER_PROVISIONING_CLUSTER_REQUEST_PAYLOAD}" -H "Authorization: Bearer ${RANCHER_AUTH_TOKEN}" -H "Content-Type: application/json" ${RANCHER_ENDPOINT}/v1/provisioning.cattle.io.clusters)
if [[ ! "$RESP" == *"$CUSTER_NAME"* ]] ; then
    echo "ERROR: failed to create import cluster in Rancher. ${RESP}"
    cleanup_and_error_out
fi

# wait for creation to finish.
# NOTE(gyee): may need to increase this value or do polling if you have a really slow
# management cluster.
sleep 20

# lookup cluster id
RESP=$(curl -s -k -H "Authorization: Bearer ${RANCHER_AUTH_TOKEN}" ${RANCHER_ENDPOINT}/v1/provisioning.cattle.io.clusters/fleet-default/$CLUSTER_NAME)
CLUSTER_ID=$(echo "$RESP" | jq -r .status.clusterName)
if [[ "$CLUSTER_ID" == "null" ]] ; then
    echo "ERROR: failed to lookup cluster ID for ${CLUSTER_NAME}. ${RESP}"
    cleanup_and_error_out
fi

# lookup the manifest URL
RESP=$(curl -s -k -H "Authorization: Bearer ${RANCHER_AUTH_TOKEN}" ${RANCHER_ENDPOINT}/v3/clusterregistrationtokens?clusterId=$CLUSTER_ID)
MANIFEST_URL=$(echo "$RESP" | jq -r .data[0].manifestUrl)
if [[ ! "$MANIFEST_URL" == *"https://"* ]] ; then
    echo "ERROR: failed to lookup manifest URL. ${RESP}"
    cleanup_and_error_out
fi

##################
# Import cluster #
##################

curl --insecure -sfL $MANIFEST_URL | kubectl --kubeconfig $WORKLOAD_CLUSTER_KUBECONF_FILE apply -f -

# wait for import to finish
# NOTE(gyee): may need to increase this value or do polling if you have a really slow
# management cluster.
sleep 120

RESP=$(curl -s -k -H "Authorization: Bearer ${RANCHER_AUTH_TOKEN}" ${RANCHER_ENDPOINT}/v1/provisioning.cattle.io.clusters/fleet-default/$CLUSTER_NAME)
CLUSTER_READY=$(echo "$RESP" | jq -r .status.ready)
if [[ "$CLUSTER_READY" == "null" ]] ; then
    echo "ERROR: cluster $CLUSTER_NAME import not successful. ${RESP}"
    cleanup_and_error_out
fi

echo "

************************************************************
Cluster ${CLUSTER_NAME} successfully imported! 
************************************************************

"

###########
# Cleanup #
###########

cleanup_files
