# slipmesh

Building blocks for running a **Talos Linux Kubernetes cluster over an obfuscated WireGuard mesh**:
[AmneziaWG](https://github.com/amnezia-vpn/amneziawg-linux-kernel-module) tunnels between sites, OSPFv3 and
iBGP over them, all brought up by Talos system extensions before kubelet starts, so the mesh never depends on
the Kubernetes API it carries.

The topology is one `slipmesh.yaml`; `slipmesh-taloscfg` turns it into a per-node `ExtensionServiceConfig`
for Talos nodes, and the same output converges a MikroTik device into the mesh.

## Repositories

**Node image pipeline.** Each repository builds and publishes on its own and consumes the others' released
images by exact tag:

| | |
| --- | --- |
| [talos-kernel](https://github.com/slipmesh/talos-kernel) | Talos kernel with `amneziawg.ko` built and signed in the same build, so `sig_enforce` stays on |
| [talos-awg-extension](https://github.com/slipmesh/talos-awg-extension) | The signed module and `ext-awg`, which configures AmneziaWG interfaces and exports per-peer metrics |
| [talos-router-extension](https://github.com/slipmesh/talos-router-extension) | BIRD and `ext-router`, which renders its OSPFv3/iBGP config and supervises it |
| [talos-nftables-extension](https://github.com/slipmesh/talos-nftables-extension) | Static `nft` and `ext-nftables`, which applies a ruleset and keeps it applied |
| [talos-installer](https://github.com/slipmesh/talos-installer) | Assembles a kernel and any set of extension images into a bootable installer |

**Everything else:**

| | |
| --- | --- |
| [talos-extensions](https://github.com/slipmesh/talos-extensions) | Rust workspace behind the three daemons, plus `slipmesh-taloscfg`, the config generator |
| [routeros](https://github.com/slipmesh/routeros) | One-shot converger that brings a MikroTik device into the mesh over the RouterOS API |
| [cni-config](https://github.com/slipmesh/cni-config) | Minimal CNI: writes a `bridge`/`host-local` conflist for the node's own podCIDR |
| [bird](https://github.com/slipmesh/bird) | Statically linked `bird`/`birdc` with `bird_exporter` in a `scratch` image, used by the router extension |
| [netlink-packet-amnezia-wireguard](https://github.com/slipmesh/netlink-packet-amnezia-wireguard) | Rust crate for the AmneziaWG generic netlink family |

Each repository's README covers how to build, configure and deploy it.

## License

MIT or Apache-2.0 at your option, except `routeros` (AGPL-3.0-only, as it links `mikrotik-rs`), `bird`
(BIRD's GPLv2-or-later) and `netlink-packet-amnezia-wireguard` (MIT, as its upstream).
