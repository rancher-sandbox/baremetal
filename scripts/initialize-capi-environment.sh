#! /bin/sh

set -o errexit
set -o nounset

: ${CLUSTER_APIENDPOINT_HOST:="127.0.0.1"}
: ${CLUSTER_APIENDPOINT_PORT:="6443"}
: ${IMAGE_CHECKSUM:="E77735e677323e547befcc290aa4308b0dcc02fb3f28e470dfe44dbbca95da35c"}
: ${IMAGE_CHECKSUM_TYPE:="sha256"}
: ${IMAGE_URL:="https://media.metal.suse.network/openSUSE-Leap-15.4.x86_64-1.0.1-NoCloud-Build2.46.qcow2"}
: ${IMAGE_FORMAT:="qcow2"}
: ${CTLPLANE_KUBEADM_EXTRA_CONFIG:=""}
: ${WORKERS_KUBEADM_EXTRA_CONFIG:=""}