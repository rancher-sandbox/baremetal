**Introduction**

This README provides an overview of the bare metal provisioning helm charts. In addition, steps are provided to deploy the helm charts and the create bare metal clusters. 

**Overview**

The top level chart for deploying Bare Metal provisioning is the metal3-deploy chart. This chart leverages additional charts in this repo as well as charts from the upstream Bitnami repository. The purpose of the  metal3-deploy chart is simply to install a set of sub charts and provide initial values and overrides (when used)
to the sub charts.

The ironic sub chart deploys ironic services used to provision the bare metal servers. This chart deploys the following containers:

    mariadb
    ironic (API)
    ironic-httpd
    ironic-inspector
    ironic-ipa-downloader
    ironic-log-watch

Relevant settings can be adjusted using the metal3-deploy values file or using an overrides file. The default behavior is to use a virtual media image to boot the bare metal server and perform the inspection. Optionally, a PXE server can be enabled to allow the server to PXE boot instead of using virtual media. When using the PXE server, the `ironic-dnsmasq` containers needs to be enabled to provide PXE support:

The baremetal-operator sub chart deploys the baremetal-operator and is pre-configured to connect to the ironic and ironic-inspector API.

The [external-dns](https://github.com/kubernetes-sigs/external-dns) (optionally installed) sub chart provides the ability to register DNS names for various services created in the host kubernetes environment. The "external-dns chart is required unless there are pre-existing methods that create DNS hostname records for the ironic ingress resources that are used in bare metal provisioning. A supported DNS provider and related settings must be specified in the metal3-deploy values file or using an overrides file. Both the ironic and bare metal-operator charts require proper name resolution of the ironic API endpoints. If not using external-dns, the "dnsConfig" section must by updated with the IP and search domain of a valid DNS server than can resolve the baremetal and ironic endpoints.

The PowerDNS sub chart (optionally installed) provides an external-dns supported DNS implementation. This chart can be deployed when there are not any other supported external-dns integrations available. When using this chart, the default pdns password and API key should be changed in the metal3-deploy values file or using an overrides file. Additionally, the corresponding entries for external-dns need to be updated. This chart installs both the PowerDNS Authoritative Server and Recursor. If not using PowerDNS, the "dnsConfig" section must by updated with the IP and search domain of the supported external-dns integrated DNS server.

The media sub chart (optionally installed) provides a webserver that can be used to serve images or any other files that can be accessed via http. This chart leverages a PV that is created on the initial host where the chart is deployed. The default host path is `/opt/media`


**Requirements**

A running kubernetes cluster

The clusterctl tool must be installed (https://cluster-api.sigs.k8s.io/user/quick-start.html#quick-start)

The cluster API core, bootstrap and control-plane providers and the infrastructure provider for metal 3 must be installed (https://github.com/metal3-io/cluster-api-provider-metal3/#deploying-the-metal3-provider)

The cluster API rke2 bootstrap provider must be installed (https://github.com/rancher-sandbox/cluster-api-provider-rke2)

A webserver to host the the virtual media image that contains the ironic-ipa. An optional media container is provided which can be used to store images.

A supported DNS option for external-dns. An optional PowerDNS implementation is included if not other supported external-dns providers are available.
  # of the external DNS server.

A DHCP server for providing IP addresses to the bare metal nodes. The assigned address/netmask/gateway must provide access to the Ironic API that is deployed. In addition, the assigned DNS server must be able to resolve the hostnames that are created using external-dns. This can be the server that is configured for external-dns or a server that will forward queries to the the external-dns configured server.



NOTE: The current implementation is not a full HA solution.  There are steps in the Installation section that can be used to handle the non HA components of the solution.







**Installing the Bare Metal Provisioning**

**Upgrading the Bare Metal Provisioning**

**Removing the Bare Metal Provisioning**

**Troubleshooting**

