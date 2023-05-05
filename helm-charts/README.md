**Introduction**

This README provides an overview of the Metal³ solution deployed via helmcharts. In addition, detailed steps are provided on how to deploy the solution via the helm charts and then create bare metal workload clusters. The provisioning of Metal³ and OpenStack Ironic is facilitated with a set of helm charts using the SLE-based container images.
Please refer to the following documentation:
- Metal³ https://github.com/metal3-io/metal3-docs to familiarize yourself with Metal³ and its features as infrastrcture provider.
- Kubernetes Cluster API https://cluster-api.sigs.k8s.io/introduction.html
- Openstack Ironic https://github.com/openstack/ironic

This baremetal provisioning solution is designed to manage the lifecyle of the Kubernetes workload clusters using the Kubernetes Cluster API workflow.


**Overview**

The helm charts are not published yet in the official helm repos. You can access these helmcharts in this repo at [helmcharts](https://github.com/rancher-sandbox/baremetal/tree/master/helm-charts)

The top level chart for deploying Bare Metal provisioning is the metal3-deploy chart. This chart leverages additional charts in this repo as well as charts from the upstream Bitnami repository. The purpose of the metal3-deploy chart is simply to install a set of sub charts and provide initial values and overrides (when used) to the sub charts.

The mariadb sub chart deploys the database container and initializes both the ironic and ironic_inspector databases.

The ironic sub chart deploys ironic services used to provision the bare metal servers. This chart deploys the following containers:

    ironic (API)
    ironic-httpd
    ironic-inspector
    ironic-ipa-downloader
    ironic-log-watch

Relevant settings can be adjusted using the metal3-deploy values file or using an overrides file. The default behavior is to use a virtual media image to boot the bare metal server and perform the inspection. Optionally, a PXE server can be enabled to allow the server to PXE boot instead of using virtual media. When using the PXE server, the `ironic-dnsmasq` containers needs to be enabled to provide PXE support:

The baremetal-operator sub chart deploys the baremetal-operator and is pre-configured to connect to the ironic and ironic-inspector API.

The [external-dns](https://github.com/kubernetes-sigs/external-dns) (optionally installed) sub chart provides the ability to register DNS names for various services created in the host kubernetes environment. The external-dns chart is *required* unless there are pre-existing methods that create DNS hostname records for the ironic ingress resources that are used in bare metal provisioning. A supported DNS provider and related settings must be specified in the metal3-deploy values file or using an overrides file. Both the ironic and bare metal-operator charts require proper name resolution of the ironic API endpoints. If not using external-dns, the "dnsConfig" section must by updated with the IP and search domain of a valid DNS server than can resolve the baremetal and ironic endpoints.

The PowerDNS sub chart (optionally installed) provides an external-dns supported DNS implementation. This chart can be deployed when there are not any other supported external-dns integrations available. When using this chart, the default pdns password and API key should be changed in the metal3-deploy values file or using an overrides file. Additionally, the corresponding entries for external-dns need to be updated. This chart installs both the PowerDNS Authoritative Server and Recursor. If not using PowerDNS, the "dnsConfig" section must by updated with the IP and search domain of the supported external-dns integrated DNS server.

The media sub chart (optionally installed) provides a webserver that can be used to serve images or any other files that can be accessed via http. This chart leverages a PV that is created on the initial host where the chart is deployed. The default host path is `/opt/media`


**Requirements**

*Pre-requistes*


- A fully functional Kubernetes management cluster in charge of running all the necessary Metal³ operators and controllers to manage the infrastructure. You can install a kubernetes cluster of your choice or setup SUSE supported cluster (https://ranchermanager.docs.rancher.com/pages-for-subheaders/kubernetes-cluster-setup).

- The clusterctl tool must be installed (https://cluster-api.sigs.k8s.io/user/quick-start.html#quick-start).

- The components cluster API core, bootstrap and control-plane providers and the infrastructure provider for Metal³ must be installed (Relevant steps from https://github.com/metal3-io/cluster-api-provider-metal3/#deploying-the-metal3-provider). As mentioned in the linked document, the cert-manager will be installed if not present.

- The cluster API rke2 bootstrap provider must be installed (https://github.com/rancher-sandbox/cluster-api-provider-rke2).


A webserver to host the the virtual media image that contains the ironic-ipa. An optional media container is provided which can be used to store images. This component can be installed via the helmcharts provided in this repo.

A supported DNS option for external-dns. An optional PowerDNS implementation is included and can be deployed using the helmcharts provided in this repo. You can also configure external-dns with other supported providers.

A DHCP server for providing IP addresses to the bare metal nodes. The assigned address/netmask/gateway must provide access to the Ironic API that is deployed. In addition, the assigned DNS server must be able to resolve the hostnames that are created using external-dns. This can be the server that is configured for external-dns or a server that will forward queries to the the external-dns configured server.

Storage backend to support data store required for mariadb data and ironic shared volume.


NOTE: The current implementation is not a full HA solution.  There are steps in the Installation section that can be used to handle the non HA components of the solution.


**Tested Versions**

| Cluster API RKE2 provider | CAPM3 Release | CAPI Release |
| --------------------------|---------------|--------------|
| v0.1.0-alpha.1            |   v1.3.0      | v1.3.5       |


**Hardware Tested against for creation of workload cluster**

HPE Gen 9 servers

**Installing the Bare Metal Provisioning**

The top level chart for deploying Metal³ solution is the metal3-deploy chart. This chart leverages additional charts in this repo as well as charts from the upstream Bitnami repository. The purpose of the metal3-deploy chart is simply to install a set of sub charts and provide initial values and overrides (when used) to the sub charts.

As part of the pre-requistes install, you will be installing many of the kubernetes tool chain like kubectl, helm etc.

Before proceeding with the deployment of Metal³, the Pre-requistes mentioned in the Requirements section of this document must be installed and ready. Please refer to the links provided in that section above for installation procedure.

Check that all the required pods and containers in the kubernetes cluster are healthy.
  ```
  kubectl get pods -A
  ```

The recommendation to deploy Metal³ solution is using the parent/umbrella helmchart metal3-deploy. However, the components can also be deployed individually.

The metal3-deploy/values.yaml provides a consistent *example* set of the override settings for all of the subcharts it manages.

Please read the description for the various entries in the metal3-deploy/values.yaml and carefully take into the following considerations:

1. Components to Install

  There are a set of components that are optional for deployment. Based on your environment needs, these optional components like the media server, powerdns, external-dns can be disabled. Check the Overview section of the document on the description of these optional components and when they can be disabled.

2. Network Infrastructure

Information related to the infrastructure setup around provioning network, DNS and DHCP must be available.
For security purposes, network segmentation is expected in production environment, which usually consist of an internal provisioning network for bare metal provisioning, and public network which is routable to the internet.


3. Storage Backend setup

  The MariaDB and the Ironic components do require the storage classes to be specified. The optional powerdns and media components use local storage on the host.
  For more on Storage Class in kubernetes, please check the official documentation (https://kubernetes.io/docs/concepts/storage/storage-classes/)


4. Non-TLS/TLS Ironic endpoints

  By default TLS is disabled. When TLS is enabled for Ironic endpoints via the enable_tls flag, the default setup is to generate a self-signed CA, and uses cert-manager to issue the certificate for access to the ironic endpoints. There are other use cases supported like letsencrypt, and secrets where the customers can bring in their own certificates for metal3 deployment to use and override the relevant setting.

5. Disabling Ingress and using IPs/Ports for the Ironic endpoints

  Currently untested but is possible to disable Ingress and just use IPs to access the ironice service endpoints in the cluster.
  
Once your metal3-deploy chart values have been formulated based on your environment into an ```overrides.yaml``` file by taking care that the relevant ironic and baremetal-operator settings match, the powerdns/external-dns setttings match, DNS domain is consistent across all the subcharts, the following steps can be used to deploy the solution:

After cloning this repo:

```console
$ cd helm-charts/metal3-deploy
$ helm dependency update .
$ helm upgrade heavy-metal . --namespace metal-cubed --create-namespace --install --values overrides.yaml
```

The helm dependency update command downloads/updates the dependent charts. Note that we have shown the use of the helm upgrade --install command for installation as it's the helm best practice to use helm upgrade --install as it installs the chart if they are not installed and upgrades them if they are already installed.

The deployment will take a while and you can check that all the required pods and containers created in the metal-cubed namespace in the kubernetes cluster are healthy.
  ```
  kubectl get pods -n metal-cubed
  ```


**Provisioning the Bare Metal workload Cluster**

Before provisioning the workload cluster, please make sure that all the pods and containers in the metal3 application are in Ready state.

Workload cluster lifecycle management is facilitated via CAPI. clusterctl CLI which is installed as part of the Pre-requistes is used to explore the workflow.

Please see https://cluster-api.sigs.k8s.io/user/quick-start.html#create-your-first-workload-cluster for more details.

Steps:

1. Create the baremetal resource using kubectl.

For example:
Here's the sample yaml definition for the bare metal host in a file name ```bmc.yaml```.

```
---
apiVersion: v1
kind: Secret
metadata:
  name: bmc-creds-1
  namespace: default
type: Opaque
data:
  username: UUUxMDI=
  password: cGFzc3dvcmQ=

---
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: bmc-1
  namespace: default
  labels:
    cluster-role: control-plane
spec:
  online: true
  bootMACAddress: 8d:dd:d4:02:30:66
  bmc:
    address: ilo4-virtualmedia://192.168.8.173
    credentialsName: bmc-creds-1
    disableCertificateVerification: true
```

Run the command to create the resource:
```console
kubectl apply -f bmc.yaml
```

Create as many bare metal host resources as in step 1 with different roles set.

2. Refer to sample clusterctl template examples in this repo which can be accessed at https://github.com/rancher-sandbox/baremetal/tree/reorganize-tree/demo/clusterctl-examples. The README details the commands to generate the sample cluster template and how to create the workload cluster.


**Upgrading the Bare Metal Provisioning**


```console
$ cd helm-charts/metal3-deploy
$ helm dependency update .
$ helm upgrade heavy-metal . --namespace metal-cubed --create-namespace --install --values overrides.yaml
```

**Removing the Bare Metal Provisioning**

The Metal³ components can be uninstalled using the helm uninstall command. By default, the uninstall command will clean up the PersistentVolumeClaims
for the MariaDB and Ironic components. However, if you do want to keep the PVCs, the ```keep``` flag under the persistence section for both metal3-mariadb and metal3-ironic charts can be set to true.

```console
$ helm uninstall heavy-metal --namespace metal-cubed
```


**Troubleshooting**


1. Mariadb/Ironic Containers Stuck in Pending State

There could be many reasons why a container may be stuck in a Pending State. The ```kubectl describe pod``` command could give us more insight into this.

For issues with PersistentVolumeClaims:
  Warning  FailedScheduling  29s   default-scheduler  0/1 nodes are available: 1 pod has unbound immediate PersistentVolumeClaims. preemption: 0/1 nodes are available: 1 Preemption is not helpful for scheduling.

Please check the storageClass configuration provided is correct and the ```kubectl get sc``` and ```kubectl get pv``` commands should provide more insight.


2. Mariadb container logs showing error:

│ + mysql_install_db --datadir=/var/lib/mysql --skip-test-db --user=root --group=60                                                           │
│ chown: changing ownership of '/var/lib/mysql': Operation not permitted                                                                      │
│ Cannot change ownership of the database directories to the 'root'                                                                           │
│ user.  Check that you have the necessary permissions and try again.

Please make sure that the storage can be read/write accessible by group 60 (mysql)

3. Provisioning errors in Ironic

To support in debugging ironic service, the openstack python-ironicclient CLI can be installed and can be used to interact with the Ironic API.
To view the details around the provisioning status of a baremetal node, you can run the ```baremetal node list ``` and to get the details of a 
particular baremetal host, ```baremetal node show <UUID>``` can be run.

The ironic sevice is setup with no auth. For the baremetal CLI to interact with the ironic endpoints, a ~/.config/openstack/cloud.yaml can be created with the 
correct endpoints.

For example:
```
clouds:
  metal3:
    auth_type: "none"
    endpoint: "http://192.168.12.232:6385"
    baremetal_introspection_endpoint_override: "http://192.168.12.232:5050"
```
