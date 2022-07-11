#! /bin/sh

set -o errexit
set -o nounset

##########################
# Required Configuration #
##########################
# These are the things you're most likely to need to override.

: ${RANCHER_HOSTNAME:="metal.suse.network"}

: ${IRONIC_DHCP_RANGE:="172.19.28.10,172.19.28.100"}
: ${IRONIC_PROVISIONING_IP:="172.19.28.2"}
: ${IRONIC_PROVISIONING_INTERFACE:="mgmt-vlan"}

##########################
# Optional Configuration #
##########################
# These all have sensible defaults that probably don't need to be
# changed... but you can, and it probably won't break things.

: ${CERT_MANAGER_HELM_RELEASE:="cert-manager"}
: ${CERT_MANAGER_NAMESPACE:="cert-manager"}

: ${CLUSTER_API_NAMESPACE:="capi-system"}

: ${EXTERNAL_DNS_HELM_RELEASE:="external-dns"}
: ${EXTERNAL_DNS_NAMESPACE:="external-dns"}
: ${EXTERNAL_DNS_DOMAIN:="${RANCHER_HOSTNAME}"}
: ${EXTERNAL_DNS_POLICY:="upsert-only"}

: ${IRONIC_CACHE_IP:="${IRONIC_PROVISIONING_IP}"}
: ${IRONIC_NAMESPACE_PREFIX:="capm3"}
: ${IRONIC_NAMESPACE:="${IRONIC_NAMESPACE_PREFIX}-system"}

: ${RANCHER_HELM_RELEASE:="rancher"}
: ${RANCHER_DEPLOYMENT:="${RANCHER_HELM_RELEASE}"}
: ${RANCHER_REPLICAS:="3"}

#########################
# Special Configuration #
#########################

# Setting this to anything other than false will cause the deployment 
# functions to upgrade existing helm deployments if they exist. It will 
# still install things if they aren't already there, though.
: ${UPGRADE:="false"}

################################
# Programs used by this script #
################################
# This ensures that everything we expect to be in $PATH, actually is.

${PROG_WHICH:="which"} \
    ${PROG_APT:="apt"} \
    ${PROG_AWK:="awk"} \
    ${PROG_CHMOD:="chmod"} \
    ${PROG_CURL:="curl"} \
    ${PROG_DPKG:="dpkg"} \
    ${PROG_ECHO:="echo"} \
    ${PROG_EGREP:="egrep"} \
    ${PROG_ENV:="env"} \
    ${PROG_ENVSUBST:="envsubst"} \
    ${PROG_FALSE:="false"} \
    ${PROG_FGREP:="fgrep"} \
    ${PROG_GETENT:="getent"} \
    ${PROG_GIT:="git"} \
    ${PROG_ID:="id"} \
    ${PROG_INSTALL:="install"} \
    ${PROG_SED:="sed"} \
    ${PROG_SH:="sh"} \
    ${PROG_SHASUM:="shasum"} \
    ${PROG_SNAP:="snap"} \
    ${PROG_SUDO:="sudo"} \
    ${PROG_SYSTEMCTL:="systemctl"} \
    ${PROG_TAR:="tar"} \
    ${PROG_TEE:="tee"} \
    ${PROG_TEST:="test"} \
    ${PROG_TPUT:="tput"} \
    ${PROG_TR:="tr"} \
    ${PROG_UNAME:="uname"} \
    ${PROG_WHOAMI:="whoami"} \
    ${PROG_XARGS:="xargs"} \
    ${PROG_WHICH} >/dev/null

###########################
# Directory Configuration #
###########################
# Everything the script puts on disk somewhere should be here.
# $PREFIX will be made writable by $OPERATOR if it isn't already.

: ${PREFIX:="/opt/local"}

: ${BINARIES:="${PREFIX}/bin"}
: ${DOWNLOADS:="${PREFIX}/downloads"}
: ${SOURCES:="${PREFIX}/src"}

: ${REPO_ROOT:=$(${PROG_GIT} -C "${0%/*}" rev-parse --show-toplevel)}

####################################################
# Programs expected to be installed by this script #
####################################################
# These will be installed by this script. They are separate from 
# the section above, because they are not expected to be installed yet.

: ${PROG_BSDTAR:="/usr/bin/bsdtar"}
: ${PROG_CLUSTERCTL:="${BINARIES}/clusterctl"}
: ${PROG_CMCTL:="${BINARIES}/cmctl"}
: ${PROG_HELM:="${BINARIES}/helm"}
: ${PROG_K9S:="${BINARIES}/k9s"}
: ${PROG_KREW:="${BINARIES}/krew"}
: ${PROG_KUBECTL:="/var/lib/rancher/rke2/bin/kubectl"}
: ${PROG_KUSTOMIZE:="${BINARIES}/kustomize"}
: ${PROG_LINKERD:="${BINARIES}/linkerd"}
: ${PROG_RKE2:="/usr/local/bin/rke2"}

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

HomeDirectoryForUser()
{
    ${PROG_GETENT} passwd "${1}" | ${PROG_AWK} -F: '{ print $6 }'
}

: ${OPERATOR:=$(${PROG_WHOAMI})}
: ${OPERATOR_HOME:=$(HomeDirectoryForUser "${OPERATOR}")}
: ${OPERATOR_UID:=$(${PROG_ID} -u ${OPERATOR})}
: ${OPERATOR_GID:=$(${PROG_ID} -g ${OPERATOR})}
: ${OPERATOR_KUBECONFIG:=${OPERATOR_HOME}/.kube/config}

######################
# Platform Detection #
######################
# Some platform-specific tooling will be installed. We need to know 
# which operating system and architecture in order to install the 
# correct versions.

: ${OS:=$(${PROG_UNAME} -s)}
: ${ARCH:=$(${PROG_UNAME} -m)}

# Packages written in Go tend to use a different naming scheme,
# so we need to account for that.
: ${GOOS:=$(${PROG_ECHO} ${OS} | ${PROG_TR} '[:upper:]' '[:lower:]')}
case ${ARCH} in
    x86_64)
        : ${GOARCH:="amd64"}
        ;;
    *)
        : ${GOARCH:="${ARCH}"}
        ;;
esac

######################
# Component Versions #
######################
# The goal of this script is to create a reproducible process, 
# not to install the latest versions of everything. To that end, all 
# components versions are defined here.

: ${BAREMETAL_OPERATOR_VERSION:="1.1.2"}
: ${CERT_MANAGER_VERSION:="1.8.1"}
: ${CLUSTER_API_VERSION:="1.1.5"}
: ${CLUSTERCTL_VERSION:="${CLUSTER_API_VERSION}"}
: ${EXTERNAL_DNS_HELM_CHART_VERSION:="6.5.6"}
# : ${EXTERNAL_DNS_VERION:="0.12.0"}
: ${HELM_VERSION:="3.9.0"}
: ${K9S_VERSION:="0.25.18"}
: ${KREW_VERSION:="0.4.3"}
: ${KUSTOMIZE_VERSION:="4.5.5"}
: ${LINKERD_VERSION:="2.11.2"}
: ${RANCHEROS_OPERATOR_VERSION:="0.1.0"}
: ${RANCHER_VERSION:="2.6.5"}
: ${RKE2_CHANNEL:="stable"}

: ${BAREMETAL_OPERATOR_TAG:="capm3-v${BAREMETAL_OPERATOR_VERSION}"}
: ${LINKERD_CHANNEL="stable"}

###########################
# Mirroring Configuration #
###########################
# This script pulls things from The Internet (TM). If that's not 
# something you want, this section should contain all remote URLs that 
# are used anywhere in this script. Additional URLs may be derived from 
# these, so consider them more as base URLs. Actually mirroring the 
# appropriate components is out of scope for this script.

# Helm Repositories
: ${CERT_MANAGER_HELM_REPO_URL:="https://charts.jetstack.io"}
: ${EXTERNAL_DNS_HELM_REPO_URL:="https://charts.bitnami.com/bitnami"}
: ${RANCHER_HELM_REPO_URL:="https://releases.rancher.com/server-charts/stable"}

# Installation Scripts
: ${HELM_UPSTREAM:="https://get.helm.sh"}
: ${RKE2_INSTALLER_UPSTREAM:="https://get.rke2.io"}

# GitHub is gets its own override, because lots of stuff comes from there.
: ${GITHUB:="https://github.com"}

: ${BAREMETAL_OPERATOR_UPSTREAM:="${GITHUB}/metal3-io/baremetal-operator"}
: ${CERT_MANAGER_UPSTREAM:="${GITHUB}/cert-manager/cert-manager/releases/download/v${CERT_MANAGER_VERSION}"}
: ${CLUSTER_API_UPSTREAM:="${GITHUB}/kubernetes-sigs/cluster-api/releases/download/v${CLUSTER_API_VERSION}"}
: ${CLUSTERCTL_UPSTREAM:="${GITHUB}/kubernetes-sigs/cluster-api/releases/download/v${CLUSTERCTL_VERSION}"}
: ${K9S_UPSTREAM:="${GITHUB}/derailed/k9s/releases/download/v${K9S_VERSION}"}
: ${KREW_UPSTREAM:="${GITHUB}/kubernetes-sigs/krew/releases/download/v${KREW_VERSION}"}
: ${KUSTOMIZE_UPSTREAM:="${GITHUB}/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}"}
: ${LINKERD_UPSTREAM:="${GITHUB}/linkerd/linkerd2/releases/download/${LINKERD_CHANNEL}-${LINKERD_VERSION}"}
: ${RANCHEROS_OPERATOR_UPSTREAM:="${GITHUB}/rancher-sandbox/rancheros-operator/releases/download/v${RANCHEROS_OPERATOR_VERSION}"}

#########################################
# Helm-specific Mirroring Configuration #
#########################################

: ${CERT_MANAGER_HELM_REPO:="jetstack"}
: ${CERT_MANAGER_HELM_CHART:="${CERT_MANAGER_HELM_REPO}/cert-manager"}

: ${EXTERNAL_DNS_HELM_REPO:="bitnami"}
: ${EXTERNAL_DNS_HELM_CHART:="${EXTERNAL_DNS_HELM_REPO}/external-dns"}

: ${RANCHER_HELM_REPO:="rancher-stable"}
: ${RANCHER_HELM_CHART:="${RANCHER_HELM_REPO}/rancher"}

##################################################
# Downloads and Archive Extraction Configuration #
##################################################
# This is all stuff for dealing with downloaded archives/scripts, 
# and how  to extract the things we need from from them. You probably
# won't need to change anything here, but releases may break things.
# When that happens, this is probably what needs to be fixed.

: ${BAREMETAL_OPERATOR_ARCHIVE:="${BAREMETAL_OPERATOR_TAG}.tar.gz"}
: ${BAREMETAL_OPERATOR_SOURCE:="${SOURCES}/baremetal-operator"}

: ${CLUSTERCTL_BINARY:="clusterctl-${GOOS}-${GOARCH}"}

: ${CMCTL_ARCHIVE:="cmctl-${GOOS}-${GOARCH}.tar.gz"}
: ${CMCTL_BINARY:="./cmctl"}

: ${HELM_ARCHIVE:="helm-v${HELM_VERSION}-${GOOS}-${GOARCH}.tar.gz"}
: ${HELM_BINARY:="${GOOS}-${GOARCH}/helm"}

: ${K9S_ARCHIVE:="k9s_${OS}_${ARCH}.tar.gz"}
: ${K9S_BINARY:="k9s"}

: ${KREW_ARCHIVE:="krew-${GOOS}_${GOARCH}.tar.gz"}
: ${KREW_ARCHIVE_CHECKSUM:="${KREW_ARCHIVE}.sha256"}
: ${KREW_BINARY:="./krew-${GOOS}_${GOARCH}"}

: ${KUSTOMIZE_ARCHIVE:="kustomize_v${KUSTOMIZE_VERSION}_${GOOS}_${GOARCH}.tar.gz"}
: ${KUSTOMIZE_BINARY:="kustomize"}

: ${LINKERD_CLI:="linkerd2-cli-${LINKERD_CHANNEL}-${LINKERD_VERSION}-${GOOS}-${GOARCH}"}
: ${LINKERD_CLI_CHECKSUM:="${LINKERD_CLI}.sha256"}

: ${RANCHEROS_OPERATOR_CHART_TARBALL:="rancheros-operator-${RANCHEROS_VERSION}.tgz"}

: ${RKE2_INSTALLER:="${DOWNLOADS}/install-rke2.sh"}

################################
# Exotic Configuration Options #
################################
# You probably shouldn't change any of these things.

: ${BAREMETAL_OPERATOR_DEPLOYMENT:="baremetal-operator-controller-manager"}
: ${BAREMETAL_OPERATOR_NAMESPACE:="baremetal-operator-system"}

: ${CERT_MANAGER_DEPLOYMENT:="cert-manager"}

: ${CLUSTER_API_BOOTSTRAP_DEPLOYMENT:="capi-kubeadm-bootstrap-controller-manager"}
: ${CLUSTER_API_BOOTSTRAP_NAMESPACE:="capi-kubeadm-bootstrap-system"}
: ${CLUSTER_API_CONTROL_PLANE_DEPLOYMENT:="capi-kubeadm-control-plane-controller-manager"}
: ${CLUSTER_API_CONTROL_PLANE_NAMESPACE:="capi-kubeadm-control-plane-system"}
: ${CLUSTER_API_CORE_DEPLOYMENT:="capi-controller-manager"}
: ${CLUSTER_API_CORE_NAMESPACE:="capi-system"}
: ${CLUSTER_API_INFRASTRUCTURE_DEPLOYMENT:="capm3-controller-manager"}
: ${CLUSTER_API_INFRASTRUCTURE_NAMESPACE:="${IRONIC_NAMESPACE}"}

: ${EXTERNAL_DNS_DEPLOYMENT:="external-dns"}

: ${IRONIC_CONTAINER_DNSMASQ:="ironic-dnsmasq"}
: ${IRONIC_DEPLOYMENT:="${IRONIC_NAMESPACE_PREFIX}-ironic"}
: ${IRONIC_HEALTH_CHECK_PATH:="boot.ipxe"}

: ${RANCHER_NAMESPACE:="cattle-system"}
: ${RANCHER_BOOTSTRAP_SECRET:="bootstrap-secret"}

: ${RANCHEROS_OPERATOR_NAMESPACE:="cattle-rancheros-operator-system"}
: ${RANCHEROS_OPERATOR_DEPLOYMENT:="rancheros-operator"}

: ${RKE2_INGRESS_CONFIG_MAP:="rke2-ingress-nginx-controller"}
: ${RKE2_INGRESS_NAMESPACE:="kube-system"}
: ${RKE2_KUBECONFIG:="/etc/rancher/rke2/rke2.yaml"}
: ${RKE2_TYPE:="server"}
: ${RKE2_SERVICE:="rke2-${RKE2_TYPE}.service"}

: ${ASSUME_ALL_PACKAGES_ARE_INSTALLED:="false"}

####################
# Helper Functions #
####################
# This script makes EXTENSIVE use of helper functions. Some of these 
# may seem trivial to you, because you understand what the commands do.
#
# Readability and maintainability are important, and these functions 
# help with both by replacing opaque commands with things that describe
# intentions. They also allow things like idempotency checks to be 
# defined in one place (per function), rather than each use.

# This particular function is a good example of how helper functions 
# can improve readability. smso and rmso refer to "stand-out" mode, 
# which is a fancy way of saying "invert the colours".
AnnounceLoudly()
{
    ${PROG_ECHO} $(${PROG_TPUT} smso) "${@}" $(${PROG_TPUT} rmso)
}

PrivilegedLogin()
{
    AnnounceLoudly Initiating Privileged Login
    ${PROG_SUDO} --user "${PRIVILEGED_USER}" --login
}

AsPrivilegedUser()
{
    AnnounceLoudly "Executing Command as Privileged User \"${PRIVILEGED_USER}\" -- ${@}"
    ${PROG_SUDO} --user "${PRIVILEGED_USER}" -- "${@}"
}

ServiceIsEnabled()
{
    ${PROG_SYSTEMCTL} is-enabled "${1}" 1>/dev/null
}

EnableService()
{
    AnnounceLoudly "Enabling Service -- ${1}"
    AsPrivilegedUser ${PROG_SYSTEMCTL} enable --now "${1}"
}

HasDirectoryAt()
{
    ${PROG_TEST} -d "${1}"
}

IsWritable()
{
    ${PROG_TEST} -w "${1}"
}

HasWritableDirectoryAt()
{
    HasDirectoryAt "${1}" && IsWritable "${1}"
}

CreateDirectoryAt()
{
    AnnounceLoudly "Creating Directory at ${1}"
    ${PROG_INSTALL} -d -m 0755 -o "${OPERATOR_UID}" -g "${OPERATOR_GID}" "${1}"
}

AsPrivilegedUserCreateDirectoryAt()
{
    AnnounceLoudly "Creating Directory at ${1}"
    AsPrivilegedUser ${PROG_INSTALL} -d -m 0755 -o "${OPERATOR_UID}" -g "${OPERATOR_GID}" "${1}"
}

EnsurePrefixExists()
{
    HasWritableDirectoryAt "${PREFIX}" \
        || AsPrivilegedUserCreateDirectoryAt "${PREFIX}"
}

EnsureDownloadsDirectoryExists()
{
    EnsurePrefixExists
    HasDirectoryAt "${DOWNLOADS}" \
        || CreateDirectoryAt "${DOWNLOADS}"
}

EnsureBinariesDirectoryExists()
{
    EnsurePrefixExists
    HasDirectoryAt "${BINARIES}" \
        || CreateDirectoryAt "${BINARIES}"
}

EnsureSourcesDirectoryExists()
{
    EnsurePrefixExists
    HasDirectoryAt "${SOURCES}" \
        || CreateDirectoryAt "${SOURCES}"
}

EnsureDirectoriesExist()
{
    EnsurePrefixExists
    EnsureDownloadsDirectoryExists
    EnsureBinariesDirectoryExists
    EnsureSourcesDirectoryExists
}

HasCommandInPath()
{
    ${PROG_WHICH} "${1}" 1>/dev/null 2>/dev/null
}

PackageIsInstalled()
{
    ${PROG_TEST} "${ASSUME_ALL_PACKAGES_ARE_INSTALLED}" = "false" || return 0
    ${PROG_DPKG} --get-selections \
        | ${PROG_AWK} -v package="${1}" \
        'BEGIN { status = 1 }
        $1 == package && $2 == "install" { status = 0 }
        END { exit status }'
}

InstallPackage()
{
    AnnounceLoudly "Installing Missing Package -- ${1}"
    AsPrivilegedUser ${PROG_APT} install -y "${@}"
}

EnsurePackageIsInstalled()
{
    PackageIsInstalled "${1}" \
        || InstallPackage "${1}"
}

SnapIsInstalled()
{
    ${PROG_SNAP} list \
        | ${PROG_AWK} -v package="${1}" \
        'BEGIN { status = 1 }
        NR > 1 && $1 == package { status = 0 }
        END { exit status}'
}

InstallSnap()
{
    SnapIsInstalled "${1}" && return
    AnnounceLoudly "Installing Missing Snap -- ${1}"
    AsPrivilegedUser ${PROG_SNAP} install "${@}"
}

EnsureSnapIsInstalled()
{
    SnapIsInstalled "${1}" \
        || InstallSnap "${1}"
}

IsExecutable()
{
    ${PROG_TEST} -x "${1}"
}

HasExecutableFileAt()
{
    HasFileAt "${1}" && IsExecutable "${1}"
}

MarkAsExecutable()
{
    AnnounceLoudly "Marking as Executable -- ${1}"
    ${PROG_CHMOD} a+x "${1}"
}

InstallExecutableFileAt()
{
    AnnounceLoudly "Installing Executable \"${1##*/}\" at ${2}"
    ${PROG_INSTALL} -D -m 0755 -o "${OPERATOR_UID}" -g "${OPERATOR_GID}" "${2}" "${1}"
}

InstallFileAt()
{
    AnnounceLoudly "Installing File at ${2}"
    ${PROG_INSTALL} -D -m 0644 -o "${OPERATOR_UID}" -g "${OPERATOR_GID}" "${2}" "${1}"
}

InstallPrivateFileAt()
{
    AnnounceLoudly "Installing Private File at ${2}"
    ${PROG_INSTALL} -D -m 0600 -o "${OPERATOR_UID}" -g "${OPERATOR_GID}" "${2}" "${1}"
}

AsPrivilegedUserInstallPrivateFileAt()
{
    AnnounceLoudly "Installing Private File at ${2}"
    AsPrivilegedUser ${PROG_INSTALL} -D -m 0600 -o "${OPERATOR_UID}" -g "${OPERATOR_GID}" "${2}" "${1}"
}

HasFileAt()
{
    ${PROG_TEST} -f "${1}"
}

IsReadable()
{
    ${PROG_TEST} -r "${1}"
}

HasReadableFileAt()
{
    HasFileAt "${1}" && IsReadable "${1}"
}

############################
# Archive Helper Functions #
############################
# See also: xkcd.com/1168

ExtractArchive ()
{
    EnsurePackageIsInstalled libarchive-tools
    archive="${1}"; shift
    ${PROG_BSDTAR} x --file="${archive}" "${@}"
}

ExtractArchiveInto()
{
    directory="${1}"; shift
    archive="${1}"; shift
    ExtractArchive "${archive}" --directory="${directory}" "${@}"
}

#############################
# Download Helper Functions #
#############################

DownloadFileTo()
{
    HasReadableFileAt "${1}" && return
    EnsureDownloadsDirectoryExists
    AnnounceLoudly "Downloading File from ${2} to ${1}"
    ${PROG_CURL} -sfL -o "${1}" "${2}"
}

# We have a DOWNLOADS directory. We could just... put things there.
DownloadFileFrom()
{
    DownloadFileTo "${DOWNLOADS}/${1##*/}" "${1}"
}

HasDownloadFrom()
{
    HasReadableFileAt "${DOWNLOADS}/${1##*/}"
}

EnsureDownloaded()
{
    HasDownloadFrom "${1}" \
        || DownloadFileFrom "${1}"
}

########################
# git Helper Functions #
########################

HasGitRepositoryAt()
{
    HasDirectoryAt "${1}/.git"
}

# Using shallow clones reduces network traffic. It's easy enough to 
# change this after the fact, but generally (in this script) we don't 
# actually care about the commit history.
CloneGitRepositoryTo()
{
    directory="${1}"
    repository="${2}"
    branch="${3}"
    depth="${4:-1}"
    HasGitRepositoryAt "${directory}" && return

    AnnounceLoudly "Cloning ${repository} (${branch}) into ${directory}"
    ${PROG_GIT} clone \
        --single-branch \
        --branch="${branch}" \
        --depth="${depth}" \
        "${repository}" "${directory}"
}

# We have a SOURCES directory. We could even put things in it!
CloneGitRepositoryFrom()
{
    directory="${SOURCES}/${1##*/}"
    EnsureSourcesDirectoryExists
    CloneGitRepositoryTo "${directory}" "${@}"
}

HasGitRepositoryFrom()
{
    HasGitRepositoryAt "${SOURCES}/${1##*/}"
}

#########################
# RKE2 Helper Functions #
#########################

DownloadRKE2Installer()
{
    HasFileAt "${RKE2_INSTALLER}" && return
    AnnounceLoudly "Downloading RKE2 Installer"
    DownloadFileTo "${RKE2_INSTALLER}" "${RKE2_INSTALLER_UPSTREAM}"
}

InstallRKE2()
{
    DownloadRKE2Installer
    IsExecutable "${RKE2_INSTALLER}" \
        || MarkAsExecutable "${RKE2_INSTALLER}"
    AnnounceLoudly "Installing RKE2 \"${RKE2_CHANNEL}\""
    AsPrivilegedUser ${PROG_ENV} \
        INSTALL_RKE2_CHANNEL="${RKE2_CHANNEL}" \
        INSTALL_RKE2_TYPE="${RKE2_TYPE}" \
        ${PROG_SH} -c "${RKE2_INSTALLER}"
    ServiceIsEnabled "${RKE2_SERVICE}" \
        || EnableService "${RKE2_SERVICE}"
}

RKE2IsInstalled()
{
    HasExecutableFileAt "${PROG_RKE2}"
}

EnsureRKE2IsInstalled()
{
    RKE2IsInstalled \
        || InstallRKE2
}

###############################
# Kubernetes Helper Functions #
###############################

InstallKubeConfig()
{
    EnsureRKE2IsInstalled
    AnnounceLoudly "Importing KUBECONFIG from RKE2 Installation"
    AsPrivilegedUserInstallPrivateFileAt "${OPERATOR_KUBECONFIG}" "${RKE2_KUBECONFIG}"
}

KubeConfigIsInstalled()
{
    HasReadableFileAt "${OPERATOR_KUBECONFIG}"
}

EnsureKubeConfigIsInstalled()
{
    KubeConfigIsInstalled \
        || InstallKubeConfig
}

HasKubernetesNamespace()
{
    EnsureKubeConfigIsInstalled
    ${PROG_KUBECTL} get namespace "${1}" 1>/dev/null 2>/dev/null
}

CreateKubernetesNamespace()
{
    EnsureKubeConfigIsInstalled
    AnnounceLoudly "Creating Missing Kubernetes Namespace -- ${1}"
    ${PROG_KUBECTL} create namespace "${1}"
}

EnsureKubernetesNamespaceExists()
{
    HasKubernetesNamespace "${1}" \
        || CreateKubernetesNamespace "${1}"    
}

HasDeploymentInNamespace()
{
    HasKubernetesNamespace "${1}" \
        && ${PROG_KUBECTL} get "deployment/${2}" --namespace "${1}" 1>/dev/null 2>/dev/null
}

WatchKubernetesRolloutInNamespace()
{
    EnsureKubeConfigIsInstalled
    ${PROG_KUBECTL} -n "${1}" rollout status "${2}"
}

#########################
# helm Helper Functions #
#########################

InstallHelm()
{
    EnsureDownloaded "${HELM_UPSTREAM}/${HELM_ARCHIVE}"
    EnsureBinariesDirectoryExists
    AnnounceLoudly "Installing helm ${HELM_VERSION} at ${PROG_HELM}"
    ExtractArchiveInto "${PROG_HELM%/*}" "${DOWNLOADS}/${HELM_ARCHIVE}" --strip-components=1 "${HELM_BINARY}"
}

HelmIsInstalled()
{
    HasExecutableFileAt "${PROG_HELM}"
}

EnsureHelmIsInstalled()
{
    HelmIsInstalled \
        || InstallHelm
}

ChartRepositoryExists()
{
    EnsureHelmIsInstalled
    ${PROG_HELM} repo list \
        | ${PROG_AWK} -v repo_name="${1}" -v repo_url="${2}" \
        'BEGIN { status = 1 }
        NR > 1 && $1 == repo_name && $2 == repo_url { status = 0 }
        END { exit status }'
}

AddChartRepository()
{
    EnsureHelmIsInstalled
    AnnounceLoudly "Adding Helm Repository \"${1}\" from ${2}"
    ${PROG_HELM} repo add "${1}" "${2}"
}

EnsureChartRepositoryExists()
{
    ChartRepositoryExists "${1}" "${2}" \
        || AddChartRepository "${1}" "${2}"
}

HasHelmReleaseInNamespace()
{
    EnsureHelmIsInstalled
    EnsureKubeConfigIsInstalled
    ${PROG_HELM} list --all-namespaces \
        | ${PROG_AWK} -v k8s_namespace="${1}" -v helm_release="${2}"  \
        'BEGIN { status = 1 }
        $1 == helm_release && $2 == k8s_namespace { status = 0 } 
        END { exit status }'
}

DeployHelmChartIntoNamespace()
{
    EnsureHelmIsInstalled
    EnsureKubeConfigIsInstalled
    namespace="${1}"; shift
    chart="${1}"; shift
    version="${1}"; shift
    release="${1}"; shift    

    if ${PROG_TEST} "${UPGRADE}" = "false"
    then if HasHelmReleaseInNamespace "${namespace}" "${release}"
        then AnnounceLoudly "Release \"${release}\" already exists in namespace \"${namespace}\", skipping deployment. Set UPGRADE=true to redeploy."
        else AnnounceLoudly "Deploying \"${release}\" from ${chart} version ${version} into \"${namespace}\""
            ${PROG_HELM} install "${release}" "${chart}" \
                --version "${version}" \
                --create-namespace \
                --namespace "${namespace}" \
                ${@:-}
        fi
    else ${PROG_HELM} upgrade "${release}" "${chart}" \
        --install \
        --version "${version}" \
        --create-namespace \
        --namespace "${namespace}" \
        ${@:-}
    fi
}

#################################
# cert-manager Helper Functions #
#################################

InstallCmctl()
{
    EnsureDownloaded "${CERT_MANAGER_UPSTREAM}/${CMCTL_ARCHIVE}"
    EnsureBinariesDirectoryExists
    AnnounceLoudly "Installing cmctl ${CERT_MANAGER_VERSION}"
    ExtractArchiveInto "${PROG_CMCTL%/*}" "${DOWNLOADS}/${CMCTL_ARCHIVE}" \
        --strip-components=1 \
        "${CMCTL_BINARY}"
}

CmctlIsInstalled()
{
    HasExecutableFileAt "${PROG_CMCTL}"
}

EnsureCmctlIsInstalled()
{
    CmctlIsInstalled \
        || InstallCmctl
}

CertManagerIsDeployed()
{
    HasDeploymentInNamespace "${CERT_MANAGER_NAMESPACE}" "${CERT_MANAGER_DEPLOYMENT}"
}

DeployCertManager()
{
    EnsureKubeConfigIsInstalled
    EnsureKustomizeIsInstalled
    AnnounceLoudly "Deploying cert-manager"
    ${PROG_KUSTOMIZE} build "${REPO_ROOT}/deploy/cert-manager" \
        | ${PROG_KUBECTL} "${1:-apply}" -f -
}

EnsureCertManagerIsDeployed()
{
    CertManagerIsDeployed \
        || DeployCertManager
}

#################################
# external-dns Helper Functions #
#################################

ExternalDNSIsDeployed()
{
    HasDeploymentInNamespace "${EXTERNAL_DNS_NAMESPACE}" "${EXTERNAL_DNS_DEPLOYMENT}"
}

DeployExternalDNS()
{
    EnsureKubeConfigIsInstalled
    EnsureKustomizeIsInstalled
    AnnounceLoudly "Deploying external-dns"
    ${PROG_KUSTOMIZE} build "${REPO_ROOT}/deploy/external-dns" \
        | ${PROG_KUBECTL} "${1:-apply}" -f -
}

EnsureExternalDNSIsDeployed()
{
    ExternalDNSIsDeployed \
        || DeployExternalDNS
}

##############################
# kustomize Helper Functions #
##############################

InstallKustomize()
{
    EnsureDownloaded "${KUSTOMIZE_UPSTREAM}/${KUSTOMIZE_ARCHIVE}"
    EnsureBinariesDirectoryExists
    AnnounceLoudly "Installing Kustomize ${KUSTOMIZE_VERSION}"
    ExtractArchiveInto "${PROG_KUSTOMIZE%/*}" "${DOWNLOADS}/${KUSTOMIZE_ARCHIVE}" "${KUSTOMIZE_BINARY}"
}

KustomizeIsInstalled()
{
    HasExecutableFileAt "${PROG_KUSTOMIZE}"
}

EnsureKustomizeIsInstalled()
{
    KustomizeIsInstalled \
        || InstallKustomize
}

############################
# linkerd Helper Functions #
############################

InstallLinkerd()
{
    EnsureDownloaded "${LINKERD_UPSTREAM}/${LINKERD_CLI}"
    EnsureDownloaded "${LINKERD_UPSTREAM}/${LINKERD_CLI_CHECKSUM}"
    EnsureBinariesDirectoryExists
    AnnounceLoudly "Installing linkerd ${LINKERD_CHANNEL}-${LINKERD_VERSION}"
    InstallExecutableFileAt "${PROG_LINKERD}" "${DOWNLOADS}/${LINKERD_CLI}"
}

LinkerdIsInstalled()
{
    HasExecutableFileAt "${PROG_LINKERD}"
}

EnsureLinkerdIsInstalled()
{
    LinkerdIsInstalled \
        || InstallLinkerd
}

#######################################
# baremetal-operator Helper Functions #
#######################################

BareMetalOperatorIsDeployed()
{
    HasDeploymentInNamespace ${BAREMETAL_OPERATOR_NAMESPACE} ${BAREMETAL_OPERATOR_DEPLOYMENT}
}

DeployBareMetalOperator()
{
    EnsureKubeConfigIsInstalled
    EnsureKustomizeIsInstalled
    AnnounceLoudly "Deploying baremetal-operator"
    ${PROG_KUSTOMIZE} build "${REPO_ROOT}/deploy/baremetal-operator" \
        | ${PROG_KUBECTL} "${1:-apply}" -f -
}

EnsureBareMetalOperatorIsDeployed()
{
    BareMetalOperatorIsDeployed \
        || DeployBareMetalOperator
}

###########################
# Ironic Helper Functions #
###########################

IronicIsDeployed()
{
    HasDeploymentInNamespace "${IRONIC_NAMESPACE}" "${IRONIC_DEPLOYMENT}"
}

DeployIronic()
{
    EnsureKubeConfigIsInstalled
    EnsureKustomizeIsInstalled

    AnnounceLoudly "Deploying Ironic"
    ${PROG_KUSTOMIZE} build "${REPO_ROOT}/deploy/ironic" \
        | ${PROG_KUBECTL} "${1:-apply}" -f -
}

EnsureIronicIsDeployed()
{
    IronicIsDeployed \
        || DeployIronic
}

###############################
# ClusterAPI Helper Functions #
###############################

InstallClusterctl()
{
    EnsureDownloaded "${CLUSTERCTL_UPSTREAM}/${CLUSTERCTL_BINARY}"
    EnsureBinariesDirectoryExists
    AnnounceLoudly "Installing clusterctl ${CLUSTERCTL_VERSION} to ${PROG_CLUSTERCTL}"
    InstallExecutableFileAt "${PROG_CLUSTERCTL}" "${DOWNLOADS}/${CLUSTERCTL_BINARY}"
}

ClusterctlIsInstalled()
{
    HasExecutableFileAt "${PROG_CLUSTERCTL}"
}

EnsureClusterctlIsInstalled()
{
    ClusterctlIsInstalled \
        || InstallClusterctl
}

ClusterAPIIsInstalled()
{
    HasKubernetesNamespace "${CLUSTER_API_NAMESPACE}"
}

ClusterAPIIsDeployed()
{
    ${PROG_TRUE} \
        && HasDeploymentInNamespace "${CLUSTER_API_CORE_NAMESPACE}"           "${CLUSTER_API_CORE_DEPLOYMENT}" \
        && HasDeploymentInNamespace "${CLUSTER_API_BOOTSTRAP_NAMESPACE}"      "${CLUSTER_API_BOOTSTRAP_DEPLOYMENT}" \
        && HasDeploymentInNamespace "${CLUSTER_API_CONTROL_PLANE_NAMESPACE}"  "${CLUSTER_API_CONTROL_PLANE_DEPLOYMENT}" \
        && HasDeploymentInNamespace "${CLUSTER_API_INFRASTRUCTURE_NAMESPACE}" "${CLUSTER_API_INFRASTRUCTURE_DEPLOYMENT}"
}

DeployClusterAPI()
{
    ClusterAPIIsInstalled && return
    EnsureClusterctlIsInstalled
    EnsureKubeConfigIsInstalled
    AnnounceLoudly "Deploying ClusterAPI ${CLUSTER_API_VERSION} with Metal3 Provider ${BAREMETAL_OPERATOR_VERSION}"
    ${PROG_CLUSTERCTL} init \
        --core "cluster-api:v${CLUSTER_API_VERSION}" \
        --bootstrap "kubeadm:v${CLUSTER_API_VERSION}" \
        --control-plane "kubeadm:v${CLUSTER_API_VERSION}" \
        --infrastructure "metal3:v${BAREMETAL_OPERATOR_VERSION}"
}

EnsureClusterAPIIsDeployed()
{
    ClusterAPIIsDeployed \
        || DeployClusterAPI
}

############################
# Rancher Helper Functions #
############################

RancherIsDeployed()
{
    HasDeploymentInNamespace "${RANCHER_NAMESPACE}" "${RANCHER_DEPLOYMENT}"
}

DeployRancher()
{
    EnsureHelmIsInstalled
    EnsureKubeConfigIsInstalled
    # EnsureKubernetesNamespaceExists "${RANCHER_NAMESPACE}"
    EnsureChartRepositoryExists "${RANCHER_HELM_REPO}" "${RANCHER_HELM_REPO_URL}"
    DeployHelmChartIntoNamespace \
        "${RANCHER_NAMESPACE}" \
        "${RANCHER_HELM_CHART}" \
        "${RANCHER_VERSION}" \
        "${RANCHER_HELM_RELEASE}" \
        --set hostname="${RANCHER_HOSTNAME}" \
        --set replicas="${RANCHER_REPLICAS}"
    WatchKubernetesRolloutInNamespace "${RANCHER_NAMESPACE}" "deployment/${RANCHER_DEPLOYMENT}"
}

EnsureRancherIsDeployed()
{
    RancherIsDeployed \
        || DeployRancher
}

GetRancherBootstrapPassword()
{
    EnsureKubeConfigIsInstalled
    AnnounceLoudly "Bootstrap Password for Rancher deployment at https://${RANCHER_HOSTNAME} is:"
    ${PROG_KUBECTL} get secret --namespace "${RANCHER_NAMESPACE}" "${RANCHER_BOOTSTRAP_SECRET}" \
        -o go-template='{{.data.bootstrapPassword|base64decode}}{{"\n"}}'
}

###################
# Optional Extras #
###################

# This is exists entirely for the benefit of the author of this script.
# None of the things this installs are actually used by the rest of the 
# script, nor is this function invoked by anything else.
InstallQualityOfLife()
{
    HasCommandInPath fish     || InstallPackage fish
    HasCommandInPath ag       || InstallPackage silversearcher-ag
    HasCommandInPath apt-file || InstallPackage apt-file
    HasCommandInPath cc       || InstallPackage clang
    HasCommandInPath pkg-config || InstallPackage pkgconf
    HasFileAt /usr/lib/${ARCH}-linux-gnu/libssl.a || InstallPackage libssl-dev

    HasCommandInPath cargo    || {
        InstallSnap --classic rustup
        rustup toolchain install stable
    }
    HasCommandInPath bat || cargo install bat

    HasCommandInPath jq       || InstallSnap jq
    HasCommandInPath yq       || InstallSnap yq
    HasCommandInPath go       || InstallSnap --classic go
    HasCommandInPath emacs    || InstallSnap --classic emacs
    HasDirectoryAt ~/.emacs.d || CloneGitRepositoryTo ~/.emacs.d "${GITHUB}/doomemacs/doomemacs" master
    HasDirectoryAt ~/.doom.d  || ~/.emacs.d/bin/doom install
}

########################
# k9s Helper Functions #
########################
# k9s is s terminal-based UI for interacting with Kubernetes clusters.

InstallK9s()
{
    EnsureDownloaded "${K9S_UPSTREAM}/${K9S_ARCHIVE}"
    EnsureBinariesDirectoryExists
    AnnounceLoudly "Installing k9s ${K9S_VERSION} at ${PROG_K9S}"
    ExtractArchiveInto "${PROG_K9S%/*}" "${DOWNLOADS}/${K9S_ARCHIVE}" "${K9S_BINARY}"
}

K9sIsInstalled()
{
    HasExecutableFileAt "${PROG_K9S}"
}

EnsureK9sIsInstalled()
{
    K9sIsInstalled \
        || InstallK9s
}

#########################
# krew Helper Functions #
#########################
# krew is package manager for kubectl plugins

# The checksum in krew's releases are just the bare hash, but shasum 
# expects a filename. This deals with that.
VerifyKrewChecksum()
{
    EnsureDownloaded "${KREW_UPSTREAM}/${KREW_ARCHIVE}"
    EnsureDownloaded "${KREW_UPSTREAM}/${KREW_ARCHIVE_CHECKSUM}"
    ${PROG_AWK} -v archive="${DOWNLOADS}/${KREW_ARCHIVE}" \
        '{ print $1 "  " archive }' \
        "${DOWNLOADS}/${KREW_ARCHIVE_CHECKSUM}" \
        | ${PROG_SHASUM} --check
}

InstallKrew()
{
    EnsureDownloaded "${KREW_UPSTREAM}/${KREW_ARCHIVE}"
    EnsureDownloaded "${KREW_UPSTREAM}/${KREW_ARCHIVE_CHECKSUM}"
    VerifyKrewChecksum
    EnsureBinariesDirectoryExists
    AnnounceLoudly "Installing krew ${KREW_VERSION}"
    ExtractArchiveInto "${PROG_KREW%/*}" "${DOWNLOADS}/${KREW_ARCHIVE}" \
        --strip-components=1 \
        -s "/-${GOOS}_${GOARCH}//" \
        "${KREW_BINARY}"
}

KrewIsInstalled()
{
    HasExecutableFileAt "${PROG_KREW}"
}

EnsureKrewIsInstalled()
{
    KrewIsInstalled \
        || InstallKrew
}

#######################################
# rancheros-operator Helper Functions #
#######################################

RancherOSOperatorIsDeployed()
{
    HasDeploymentInNamespace "${RANCHEROS_OPERATOR_NAMESPACE}" "${RANCHEROS_OPERATOR_DEPLOYMENT}"
}

DeployRancherOSOperator()
{
    ${PROG_HELM} install rancheros-operator "${RANCHEROS_OPERATOR_UPSTREAM}/${RANCHEROS_OPERATOR_CHART_TARBALL}" \
        --create-namespace \
        --namespace cattle-rancheros-operator-system
}

EnsureRancherOSOperatorIsDeployed()
{
    RancherOSOperatorIsDeployed \
        || DeployRancherOSOperator
}

########################
# Diagnostic Functions #
########################

ShowIronicDHCP()
{
    ${PROG_KUBECTL} exec "deployment/${IRONIC_DEPLOYMENT}" \
        -n "${IRONIC_NAMESPACE}" \
        -c "${IRONIC_CONTAINER_DNSMASQ}" \
        -- cat /var/lib/dnsmasq/dnsmasq.leases

}

GenerateBareMetalHosts()
{
    ShowIronicDHCP \
    | ${PROG_AWK} \
    -v PROG_ENV="${PROG_ENV}" \
    -v PROG_ENVSUBST="${PROG_ENVSUBST}" \
    -v TEMPLATE=/opt/hacks/template.yaml \
    '$4 ~ /^ILO/ { sub(/^ILO/,"",$4); print PROG_ENV, "name="tolower($4),"mac="$2, PROG_ENVSUBST, "<", TEMPLATE }' \
    | ${PROG_XARGS} -r -d "\n" -n 1 -- ${PROG_SH} -c
}

################
# Main Program #
################

InstallOptionalTools()
{
    EnsureK9sIsInstalled
    EnsureKrewIsInstalled
}

Default()
{
    EnsureDirectoriesExist
    EnsureRKE2IsInstalled
    EnsureKubeConfigIsInstalled
    EnsureHelmIsInstalled
    EnsureKustomizeIsInstalled
    EnsureCertManagerIsDeployed
    EnsureExternalDNSIsDeployed
    EnsureIronicIsDeployed
    EnsureBareMetalOperatorIsDeployed
    EnsureClusterAPIIsDeployed
    EnsureRancherIsDeployed
    EnsureRancherOSOperatorIsDeployed
}

${PROG_TEST} "${DEBUG:-false}" = "false" || set -o xtrace

eval "${@:-Default}"
