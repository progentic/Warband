# Warband local Linux VM preparation

The installed Homebrew Lima is the development VM manager. `lima.yaml` records an ARM64 VZ development profile for this Apple Silicon host. This does not select the production architecture or certify the x64 CI build.

Provisioning is blocked. `selection.json` has no guest image URL or digest, and `lima.yaml` has no image. Select a reviewed image and record its SHA-256 before rendering a runnable recipe or creating a VM. The primary Linux CI build remains x64 on `ubuntu-latest`.

The prepared profile disables mounts entirely, including the host home directory. Plain mode disables default mounts and automatic port forwarding; all guest application port ranges are also ignored. No container runtime, provider keys, runtime account, or production service is configured. A future guest can receive a source copy without exposing the host home directory. If a project mount becomes necessary, explicitly mount only this repository and review the resulting config.

Future Lima commands must use a project-local `LIMA_HOME` pointing to `.local/lima`, and a project-local cache location supported by the installed Lima version. Do not use default home-directory VM state. Image downloads and generated configuration belong under `.local/`. No VM was created by Phase 1 implementation.

`bash vm/validate.sh` scopes validation state to this project and deliberately fails while the required image is unset. It does not expose a start/provision command. The installed Lima validator reports `field images must be set`; this is the expected provisioning block, not a successful runnable-VM check.

## x64 verification profile

`x64-review.yaml` adds a separate full-system QEMU development guest for Phase 1 x64 Linux verification. Its image release and SHA-256 are recorded in `x64-review-selection.json`; the host copy is verified before creation. Invoke Lima from this repository root with project-local `LIMA_HOME`. The profile uses a local image, so Lima does not write its image download cache in the host home directory. Plain mode disables guest agents, mounts, container runtimes, and application forwarding. SSH management binds only to loopback. Production architecture remains unset.

Local guest networking required a temporary loopback relay to Canonical HTTPS archives, retaining Ubuntu archive signature and package hash validation. This transport is local verification scaffolding under `.local/review`, not a runtime adapter or a CI dependency. Stop the relay and VM after collecting results.
