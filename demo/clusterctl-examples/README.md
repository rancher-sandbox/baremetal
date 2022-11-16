# Table Of Contents

- [Overview](#overview)
  - [OS Image](#os_image)
  - [Network Configurations](#network_configurations)
  - [Network Access](#network_access)
  - [User Accounts](#user_accounts)
- [Prerequsites](#prerequisites)
- [How-To](#how_to)
- [Import Workload Cluster Into Rancher](#import_workload_cluster_into_rancher)

# Overview <a name="overview" />

This directory contains sample [clusterctl templates][clusterctl-templates] for
both [cri-o][cri-o] and [rke2][rke2] clusters. The boostrapping and
configuration of these clusters will be largely depended on the following:

## OS Image <a name="os_image" />

The type of OS image (i.e. SUSE-based, Ubuntu-based, etc) and what's on that
image (i.e. packages pre-installed, package availability, networking setup,
security setup, user accounts setup, etc) will determine what the cluster
bootstrapping commands will look like.

## Network Configurations <a name="network_configurations" />

The network configuration is very much environment-specific. *The NIC names
for the baremetal nodes must be consistent as they are sharing the same
Metal3DataTemplate*. For example, we can't have a NIC in one node named
`eno1f0` while the other node have it as `eth0`.

Furthermore, the configuration of IP pools, gateways, DNS, and routing table
requires indepth knowledge of infrastructure networking setup.

The samples are were tested with the following network configurations.

The control plane node has two networks, one is the provisioning network which
is internal (i.e. 192.168.0.0/24) and a VLAN network (with VLAN ID 1076) which
has routes to public endpoints. The NIC names for the control plane node are
expected to be `eno1f0` and `eno1f1.1076`.

Likewise, the worker node also sharing the same two network. However, the NIC
names for the worker node are `eno49` and `eno19.1076`.

## Network Access <a name="network_access" />

Whether the baremetal provisioning network have public network egress or not
(i.e. air-gapped environment) will also influence the cluster bootstrapping
commands. For an air-gapped environment, any public endpoints will need to be
updated to their respective internal endpoints.

## User Accounts <a name="user_accounts" />

The bootstrapping commands may also depended on certain user accounts (for
management and monitoring purposes as an example).

# Prerequsites <a name="prerequisites" />

The samples were validated based on the following:

1. Ubuntu Jammy OS image. The samples were validated using an vanilla Ubuntu
   image built by disk image builder. For example:

   ```console
   disk-image-create ubuntu vm block-device-efi dhcp-all-interfaces devuser -o ubuntu_22.04-efi
   ```
2. Two network-connected bare metal nodes, one for the control plane and the
   other for worker.

# How-To <a name="how_to" />

To generate a cri-o cluster with CAPM3 version `v1beta1` and CAPI version
`v1beta1`:

1. edit `sample-kubeadm-ctlplane-crio-ubuntu.rc` to make sure the configuration
   matches your particular environment. All the options are self-documented.

2. source `sample-kubeadm-ctlplane-crio-ubuntu.rc`

   ```console
   source sample-kubeadm-ctlplane-crio-ubuntu.rc
   ```

3. generate the cluster YAML with `clusterctl` command. For example:

   ```console 
   clusterctl generate cluster sample-cluster --target-namespace metal3 --from sample-clusterctl-template-v1beta1-kubeadm-ctlplane.yaml --control-plane-machine-count 1 --kubernetes-version v1.25.2 --worker-machine-count 1 > simple-cluster.yaml
   ```
4. create the cluster with `kubectl` command. For example:

   ```console
   kubectl apply -f simple-cluster.yaml
   ```

To generate a RKE2 cluster with CAPM3 version `v1beta1` and CAPI version
`v1beta1`:

1. edit `sample-rke2-ctlplane-ubuntu.rc` to make sure the configuration
   matches your particular environment. Each option is self-documented.

2. source `sample-rke2-ctlplane-ubuntu.rc`

   ```console
   source sample-rke2-ctlplane-ubuntu.rc
   ```

3. generate the cluster YAML with `clusterctl` command. For example:

   ```console 
   clusterctl generate cluster sample-cluster --target-namespace metal3 --from sample-clusterctl-template-v1beta1-rke2-ctlplane.yaml --control-plane-machine-count 1 --kubernetes-version v1.25.3+rke2r1 --worker-machine-count 1 > simple-cluster.yaml
   ```
4. create the cluster with `kubectl` command. For example:

   ```console
   kubectl apply -f simple-cluster.yaml
   ```

# Import Workload Cluster Into Rancher <a name="import_workload_cluster_into_rancher" />

If you want your workload (RKE2) cluster to be managed by Rancher, you must
import it into Rancher. You may use the `import_cluster_into_rancher.sh`
BASH shell script to for that purpose. The script must be executed in an
environment where both `clusterctl` and `kubectl` CLI available and are
configured to access the management cluster. To import a workload cluster,
for example:

```console
import_cluster_into_rancher.sh --cluster-name my-cluster --rancher-username admin --rancher-password fymAOf1sVC0CWaloRpJM --rancher-endpoint https://suse.baremetal
```
You may use the environment variable `RANCHER_PASSWORD` to convey the
Rancher password instead of specifying it at the command line. For example:

```console
export RANCHER_PASSWORD=fymAOf1sVC0CWaloRpJM
import_cluster_into_rancher.sh --cluster-name my-cluster --rancher-username admin --rancher-endpoint https://suse.baremetal
```

[clusterctl-templates]: https://cluster-api.sigs.k8s.io/clusterctl/commands/generate-cluster.html#alternative-source-for-cluster-templates
[cri-o]: https://cri-o.io/
[rke2]: https://docs.rke2.io/
