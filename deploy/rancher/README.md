# Rancher Deployment

This directory deploys [Rancher](https://github.com/rancher/rancher), with some unsupported modifications.

We want valid TLS Certificates, and Rancher supports [LetsEncrypt](https://letsencrypt.org/), but only using [HTTP-01 Challenges](https://letsencrypt.org/docs/challenge-types/#http-01-challenge).

However, our lab environment is not reachable from The Internet, so we need to use [DNS-01 Challenges](https://letsencrypt.org/docs/challenge-types/#dns-01-challenge).

So this [deploys Rancher from the standard Helm Chart](./kustomization.yaml) with a [small patch to the Issuer](./patch/Issuer/rancher.yaml).

You can deploy this with either the `EnsureRancherIsDeployed` function in the [headnode script](/scripts/script.sh), or manually from the repo root with:

```shell
kustomize build deploy/rancher | kubectl apply -f -
```
