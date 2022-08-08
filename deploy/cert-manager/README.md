# cert-manager

We need certs, and we use [cert-manager](https://cert-manager.io/) to handle 'em.

This is a [straightforward deployment](./kustomization.yaml), with the following configuration specific to our environment:

- The ClusterIssuer is [configured](./resource/ClusterIssuer/letsencrypt-prod.yaml) to use [DNS-01 Challenges](https://letsencrypt.org/docs/challenge-types/#dns-01-challenge), since our lab environment is not reachable from The Internet.
- We are using [Cloudflare](https://www.cloudflare.com/) as our DNS provider, and the credentials for this are stored in a [templated Secret](/templates.d/cert-manager/resource/Secret/dns-provider-credentials.yaml.gomplate).

You can deploy this with either the `EnsureCertManagerIsDeployed` function in the [headnode script](/scripts/script.sh), or manually from the repo root with:

```shell
kustomize build deploy/cert-manager | kubectl apply -f -
```
