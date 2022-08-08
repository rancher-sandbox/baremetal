# Lab-Specific Hacks

This directory contains all the hacks that are specific to our lab environment. This includes routing iLO interfaces through in-cluster Ingress routes for TLS termination, to sidestep the vintage ciphers used by the hardware.

## If you're not running this in our lab, you don't need this.

You can deploy this with the `DeployHacks` function in the [headnode script](/scripts/script.sh), or manually from the repo root with:

```shell
kustomize build deploy/hacks | kubectl apply -f -
```
