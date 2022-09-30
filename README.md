# Metal3 deployment and demo Scripts and Manifests

This repo contains (almost) everything needed to get a working metal3
deployment up and running and demo bare metal provisioning.

Short version is that stuff in `scripts` is executable, `scripts/script.sh` is the main deploy script that does all the work. If you wanna read it, start at the bottom in the `Default` function to see what it does if you give it no args. Otherwise it calls whatever function you pass as args.

Stuff in `deploy` is all the Kube YAML stuff. It's grouped by deployable thing, so `ironic`, `rancher`, etc. `script.sh` does the deploying of those things, which is typically just `kustomize build | kubectl apply -f -`.

For anything that looks like it's a missing file in the repo, like `Secrets`, check `templates.d`, which mirrors the same hierarchy as `deploy`. Those get rendered from `templates.d` into `deploy` using `scripts/render-templates.sh`.

`ipa-patcher` has a Dockerfile and script that captures the manual stuff I was doing to patch the busted systemd unit in the IPA initramfs.

The script should work on ANY Ubuntu 22.04 host, since all the hardware-specific stuff is done by Ironic. And the only Ubuntu-specific bits are the parts where it installs packages if they're missing.
