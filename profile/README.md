# slipmesh

Building blocks for running a **Talos Linux Kubernetes cluster over an obfuscated WireGuard mesh**:
[AmneziaWG](https://github.com/amnezia-vpn/amneziawg-linux-kernel-module) tunnels between sites, OSPFv3 and
iBGP over them, all brought up by Talos system extensions before kubelet starts, so the mesh never depends on
the Kubernetes API it carries.

The topology is one `slipmesh.yaml`; `slipmesh-taloscfg` turns it into a per-node `ExtensionServiceConfig`
for Talos nodes, and the same output converges a MikroTik device into the mesh.

## Repositories

**Node image pipeline.** Each repository builds and publishes on its own; the installer consumes the
others' released images by exact pin:

| | |
| --- | --- |
| [talos-kernel](https://github.com/slipmesh/talos-kernel) | Talos kernel with `amneziawg.ko` built and signed in the same build, so `sig_enforce` stays on |
| [talos-extensions](https://github.com/slipmesh/talos-extensions) | Rust workspace behind the `ext-awg`, `ext-router` and `ext-nftables` daemons, plus `slipmesh-taloscfg`, the config generator |
| [talos-installer](https://github.com/slipmesh/talos-installer) | Builds the system extensions around those daemons, with static BIRD and `nft`, and bakes them with the kernel into a bootable installer |

**Everything else:**

| | |
| --- | --- |
| [routeros](https://github.com/slipmesh/routeros) | One-shot converger that brings a MikroTik device into the mesh over the RouterOS API |
| [cni-config](https://github.com/slipmesh/cni-config) | Minimal CNI: writes a `bridge`/`host-local` conflist for the node's own podCIDR |
| [netlink-packet-amneziawg](https://github.com/slipmesh/netlink-packet-amneziawg) | Rust crate for the AmneziaWG generic netlink family, built on `netlink-packet-wireguard` |

Each repository's README covers how to build, configure and deploy it.

## License

MIT or Apache-2.0 at your option, except `routeros` (AGPL-3.0-only, as it links `mikrotik-rs`) and
`netlink-packet-amneziawg` (MIT, as `netlink-packet-wireguard`). The images `talos-installer` builds also
carry third-party software, such as BIRD, under its own licenses.
