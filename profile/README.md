# slipmesh

Building blocks for running a **Talos Linux Kubernetes cluster over an obfuscated
WireGuard mesh** — DPI-resistant AmneziaWG tunnels between sites, with OSPFv3 and iBGP
running over them, brought up by Talos system extensions rather than by anything inside
Kubernetes.

Everything here is generic: the topology lives in one YAML file you write, and nothing in
these repositories knows anything about a particular cluster, provider or site.

## The deployment this targets

Nodes in different providers, different countries, no L2 adjacency between them, no VPC
spanning them, and networks along the way that plain WireGuard doesn't reliably cross.
Four constraints follow, and they shape every design decision in the org:

- **The overlay has to come up before Kubernetes does.** If the API server endpoint is
  reachable only *through* the mesh, then whatever establishes the mesh cannot depend on
  the Kubernetes API — that would be circular. So the tunnels, the routing daemon and the
  firewall are Talos *extension services*, configured from static files in the machine
  config and running before kubelet.
- **The tunnels have to be obfuscated.**
  [AmneziaWG](https://github.com/amnezia-vpn/amneziawg-linux-kernel-module) is a WireGuard
  fork whose handshake doesn't look like WireGuard's on the wire. It's an out-of-tree
  kernel module, and Talos enforces module signatures — so the module is compiled and
  signed inside the same build as the kernel that will load it, and `sig_enforce` never
  has to be turned off.
- **Reachability has to be dynamic.** Every node runs BIRD: OSPFv3 over the mesh links'
  link-local addresses makes the per-node loopbacks reachable, then a full-mesh iBGP over
  those loopbacks (RFC 8950 extended next hop) carries the IPv4 pod and service prefixes.
  Losing a tunnel reroutes instead of partitioning, and no node holds a static route to
  another.
- **Not every mesh member is a Talos node.** A MikroTik device can terminate mesh links
  and speak the same OSPF/iBGP, converged over the RouterOS API from the same generated
  config the Talos nodes get.

## How the pieces fit

One file — `mesh.yaml` — is the source of truth for the topology: links, ports,
obfuscation parameters, BGP AS, road-warrior clients, firewall ruleset. A generator turns
it into a per-node `ExtensionServiceConfig` for `awg` / `router` / `nftables`, which is
what `talosctl apply-config` ships to the node. The same generated file drives the
RouterOS converger.

```text
mesh.yaml ──► patches ──► <node>.yaml ──► talosctl apply-config ──► awg / router / nftables
                    └────► <device>.yaml ──► routeros ─────────────► MikroTik device
```

```yaml
# mesh.yaml, in full — three nodes and a triangle of links
cluster:
  bgp_as: 64512
  loopback_networks: {ipv4: "10.62.0.0/24", ipv6: "fd00:dead:beef::/120"}
  tunnel_networks:   {ipv4: "10.62.1.0/24", ipv6: "fe80:dead:beef::/120"}
  service_subnet: "10.60.0.0/16"
  pod_subnet: "10.61.0.0/16"
  direct_interfaces: ["mesh-*"]

nodes:
  - {name: node-a, node_id: "0.0.0.1", endpoint: "203.0.113.10"}
  - {name: node-b, node_id: "0.0.0.2", endpoint: "203.0.113.20"}
  - {name: node-c, node_id: "0.0.0.3", endpoint: "203.0.113.30"}

mesh:
  links:
    - {pair: [node-a, node-b], port: 52801}
    - {pair: [node-b, node-c], port: 52802}
    - {pair: [node-c, node-a], port: 52803}
```

Addresses, keys and obfuscation parameters are all derived or generated from that — you
name the nodes and the links, not the individual interfaces.

## Repositories

**Node image pipeline** — five repositories, each building and publishing independently.
None of them check out or build another's source; they consume each other's *published*
OCI images, pinned by exact release tag:

| | |
| --- | --- |
| [talos-kernel](https://github.com/slipmesh/talos-kernel) | Talos kernel with `amneziawg.ko` compiled and signed alongside it, in one build session |
| [talos-awg-extension](https://github.com/slipmesh/talos-awg-extension) | System extension: the signed module + the `awg` daemon that configures interfaces from it |
| [talos-router-extension](https://github.com/slipmesh/talos-router-extension) | System extension: statically-linked BIRD + the `router` daemon that drives it |
| [talos-nftables-extension](https://github.com/slipmesh/talos-nftables-extension) | System extension: statically-linked `nft` + a daemon that applies and re-applies the ruleset |
| [talos-installer](https://github.com/slipmesh/talos-installer) | Assembles a kernel image and N extension images into a bootable Talos installer. Knows nothing about which extensions it's given |

**Code that runs on the nodes:**

- [talos-extensions](https://github.com/slipmesh/talos-extensions) — the Rust workspace
  behind all three extensions: `awg` (AmneziaWG interfaces over netlink, no `wg` binary),
  `router` (renders BIRD config, supervises BIRD, speaks its control-socket protocol
  directly — no `birdc`), `nftables` (applies a ruleset, then stays resident watching for
  something else on the node clobbering its tables), and `patches`, the `mesh.yaml`
  generator.
- [routeros](https://github.com/slipmesh/routeros) — one-shot converger that brings a
  MikroTik device to the desired state over the RouterOS binary API. Not a Kubernetes
  client, no daemon: it runs like `ansible-playbook`, with `--check`/`--diff`.
- [cni-config](https://github.com/slipmesh/cni-config) — DaemonSet that reads the node's
  own `Node.spec.podCIDRs` and writes a `bridge`/`host-local` CNI conflist for it. The
  plugins already ship with Talos; only this file was missing. A cluster needs a CNI, and
  this is the smallest one that fits — but any CNI works, since the mesh announces the
  node's podCIDR by watching the kernel routing table for that prefix rather than by
  naming the CNI's interface.
- [bird](https://github.com/slipmesh/bird) — statically-linked `bird`/`birdc` as a
  `scratch` image, for running BIRD as a sidecar. Predates the extension pipeline, which
  builds its own BIRD from source.

**Superseded**: the first version of this managed the mesh with Kubernetes operators
driven by CRDs. That works for nodes which have already joined a cluster, and not at all
for the boot-time path that has to exist first, so it was replaced by the extensions above
and its repositories were retired.

## Using it

Each repository's README is self-contained and carries its own build and release
instructions. The short path:

1. **Get an installer image.** Either build the pipeline yourself — `talos-kernel`, then
   the extensions you want, then `talos-installer` (all of it needs only Docker with
   `buildx`, on any machine, for either architecture) — or start from published images and
   pick your own combination in `talos-installer`.
2. **Describe your topology** in a `mesh.yaml` like the one above, and generate per-node
   patches with `patches` from `talos-extensions`.
3. **Apply them** with `talosctl apply-config`, alongside your own machine config. The
   generator preserves any document it doesn't own, so hand-written per-node settings
   survive regeneration.
4. **Give the cluster a CNI** — `cni-config`, or any other: the mesh announces each node's
   podCIDR by prefix, not by interface name, so the choice is yours. Optionally converge a
   MikroTik device into the same mesh with `routeros`.

The extensions are independent of each other: nothing forces you to take all three, and
`talos-installer` takes whatever list of extension images you hand it.

## Recurring design rules

- **Nothing floating.** Every dependency is a pinned commit, version or release tag — no
  `latest`, no `main`, no reconstructing a tag from shared variables.
- **Loud over silently wrong.** Required inputs have no defaults: a build that would
  produce a subtly wrong image fails at the first step instead of shipping.
- **`scratch` extensions.** Each extension image holds one statically-linked binary set
  and nothing else, which is why BIRD and `nft` are built from source rather than taken
  from distribution packages.
- **Comments carry the *why*.** Non-obvious pins, workarounds and dead ends are written
  down next to the code, along with how they were confirmed on a real node.

## License

MIT or Apache-2.0, at your option, across the org — except `routeros`, which is
AGPL-3.0-only (it links `mikrotik-rs`), and `bird`, which carries BIRD's own GPLv2-or-later.
