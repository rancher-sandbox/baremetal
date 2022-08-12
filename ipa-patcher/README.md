# ironic-python-agent initramfs patcher

This contains a containerized version of a manual process for patching an error in the upstream IPA initramfs.

In the upstream release (at the time this was scripted, it may have been fixed since), the [Unit Configuration](https://www.freedesktop.org/software/systemd/man/systemd.unit.html) for `openstack-ironic-python-agent.service` sets [StandardOutput](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#StandardOutput=) to `tty`, when it should be `inherit`. This causes the service to fail. Since this service is the primary function of booting into this image... this is a significant problem.

Fortunately, the solution itself is simple: change the value.

Unfortunately, our inputs are a [tarball](https://en.wikipedia.org/wiki/Tar_(computing)) containing a kernel and a gzipped initramfs (which is itself a [cpio](https://en.wikipedia.org/wiki/Cpio) archive), and ironic expects a checksum for that archive. So we unpack it, fix the one problematic line, repack it, and regenerate the checksums.

Doing this by hand isn't particularly **hard**, but it's tedious, so there's a [script](./ipa-patcher.sh) to make it reproducible. Since that depends on some stuff that may not be installed by default (notably [libarchive](https://libarchive.org/)), there's a [dockerfile](./Dockerfile) that bundles all the dependencies and some configuration to make it more container-friendly.

Since you probably want to **collect** the resulting outputs, you should probably mount a volume at `/mnt/outputs` (or set `OUTPUTS` appropriately in the environment if you mount it somewhere else).

If you want to cache inputs across executions, mount something at `/mnt/inputs` (or set `INPUTS` in the environment to wherever you mount your persistence to).

Inputs will be downloaded if they are not already present. If you want to force them to be redownloaded, set `FORCE` in the environment to any non-`false` value.
