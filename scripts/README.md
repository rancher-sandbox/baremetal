# Scripts

## audit.sh

This is for auditing how the files embedded in our `ConfigMap`s diverge
from the ones in the upstream ironic container images. This is for
developers, or the generally curious. You don't need this for deployment.

## render-templates.sh

This script renders the templates from `templates.d/` into `deploy/`.
At the time of this writing, this is just used for `Secret`s, though it
will render any other templates you put in there.

## script.sh

This deploys everything, end to end. There's a lot you can configure,
but the only things you NEED to configure are the ones where there's
no sane default. Defaults are set, but they're not really SANE, they're
just the ones that reflect the testing environment.

```shell
: ${RANCHER_HOSTNAME:="metal.suse.network"}
: ${IRONIC_DHCP_RANGE:="172.19.28.10,172.19.28.100"}
: ${IRONIC_PROVISIONING_IP:="172.19.28.2"}
: ${IRONIC_PROVISIONING_INTERFACE:="mgmt-vlan"}
```
