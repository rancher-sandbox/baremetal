# Internal Installation Media Server

This directory deploys the a simple HTTP server to service static assets. Specifically, it serves up the [IPA tarball](/ipa-patcher) that Ironic uses to build ISOs (these are also used to boot via PXE if you're doing that), and whatever installation ISOs you happen to be using.

You can deploy this with either the `EnsureMediaIsDeployed` function in the [headnode script](/scripts/script.sh), or manually from the repo root with:

```shell
kustomize build deploy/media | kubectl apply -f -
```
