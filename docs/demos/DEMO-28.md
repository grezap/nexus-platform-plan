# DEMO-28 · Day-2 capacity ops from the CLI — vertical resize, a cluster-safety gate, and a guarded restore

## 1. What this shows

The batch-3 completion pass closed the last of the "big" `nexus-cli` gaps by implementing three
day-2 operator verbs **inside the tool**, with no out-of-band hops: **`scale-up`** (vertical VM resize —
the whole verb was a skeleton before), the **cluster-safety gate** that keeps a resize from
power-cycling a write-primary, and a **guarded `backup restore`** for the Swarm orchestration tier.

The single insight: these are the operations that are easy to do *dangerously* — resizing a box means
powering it off; restoring a snapshot means overwriting live state — so the CLI does them **safely and
honestly**. `scale-up` refuses the current primary/leader unless you force it, grows a disk but tells you
plainly when it *didn't* extend the filesystem (rather than faking success), and swarm `restore` refuses
to overwrite the live cluster without an explicit second opt-in.

Personas: **SRE** (right-size a node, restore a tier, without a footgun), **platform engineer** (one tool
for capacity changes across every tier — the resizer is generic), **DevOps** (the safety gates are the
reviewable, testable guardrails around destructive ops).

## 2. Runtime + prerequisites

- **Environment target** — the always-on foundation base (6 VMs) plus, per step, the specific tier being
  operated: OLTP **redis** (6 VMs) for the resize walkthrough, **kafka-east** (3 VMs) for the gate,
  **swarm** (6 VMs) for the guarded restore. Only the tier under test needs to be up.
- **VMs required** — `redis-1..6` · `kafka-east-1..3` · `swarm-manager-1..3` + `swarm-worker-1..3` (exact
  names in [`docs/infra/vms.yaml`](../infra/vms.yaml)).
- **Build host** — **Windows** with `vmrun` **and** `vmware-vdiskmanager` on PATH (resolved by
  `VmrunPaths`); `scale-up` is a build-host operation (it stops/edits/starts the `.vmx`).
- **Env vars** — `NEXUS_SSH_KEY` · `NEXUS_VMS_YAML` (all tiers); `VAULT_ADDR`/`VAULT_TOKEN`/`VAULT_CACERT`
  (kafka + swarm control planes). `nexus-cli/scratch/nx.ps1` sets these.
- **Seed data** — none.
- **Expected duration** — 6–9 min (each `scale-up` cold-restart of a VM dominates at ~30–60 s).
- **Reset command** — the resize walkthrough is a round-trip (scales back down); the gate step is
  non-destructive (exit 2, no VM touched); the swarm restore self-restores a fresh, identical snapshot.

## 3. Architecture snapshot

`scale-up` is a **generic** verb (`VmrunVmResizer`) — one implementation over every VM, not per-adapter.
CPU/RAM change via `vmrun stop` → an **atomic `.vmx` edit** (`numvcpus`/`memsize`) → **cold** start; disk
via **`vmware-vdiskmanager -x`** (offline, grow-only) → a **SAFE** in-guest FS extend gated by
`growpart --dry-run` (never repartitions a live boot disk). Before any of that, the resizer resolves the
VM's **owning cluster adapter** (1:1 by vms.yaml cluster, plus the documented splits
`sqlserver`/`sqlserver-ag`, `foundation`→`vault`/`foundation-ad`, `platform-tools`→`registry`), warms its
status, and asks `CanResizeVm` — refusing the current primary/leader unless `--force-primary`. The Swarm
`backup restore` runs `consul`/`nomad snapshot restore` online against the raft leader, behind an explicit
`--confirm-destructive` flag on top of `--yes`.

## 4. Walkthrough (operator commands)

> Driven via `nexus-cli/scratch/nx.ps1` (sets the runtime env, calls the freshly built `nexus.exe`).
> The executable System B demos are cited per row.

| # | Command | What you see | WHERE observed · What it proves |
|---|---------|--------------|---------------------------------|
| 1 | `nexus status redis --json` | Each node's **live** role; the resize target (redis-1) is currently a `replica`. | The CLI · vms.yaml labels redis-1 the shard1 primary by design, but Redis roles drift — the gate reads the **live** role, so you confirm it first. `DEMO-17`. |
| 2 | `nexus scale-up redis-1 --cpu 4 --ram 3072 --yes --json` | `outcome=ok`; `oldCpu 2 → newCpu 4`, `oldRamMb 2048 → newRamMb 3072`; ~30–60 s. | stdout + the guest (`ssh … 'nproc; free -m'` → 4 CPUs / ~3 GB) + the VMware library. A real, bidirectional vertical resize via an atomic `.vmx` edit + cold restart; the shard's surviving primary is untouched. **Live-verified 2026-07-05.** `DEMO-17`. |
| 3 | `nexus scale-up redis-1 --cpu 2 --ram 2048 --yes --json` | Scales back to 2 / 2048; re-running the same values → `outcome=skipped`. | stdout · the resize is reversible + idempotent (right-sized per the prefer-less-memory rule). |
| 4 | `nexus scale-up redis-1 --disk 42 --yes --json` | `outcome=ok`, `newDiskGb 42`, **plus** a warning: *"vmdk grown to 42 GB, but the in-guest root filesystem was NOT auto-extended … root is not the last partition …"*. | stdout · the vmdk grows but the deb13 swap-after-root layout can't be extended in place, so the FS is left alone and **reported honestly** — no false success. Confirm with `ssh … lsblk`: disk 42 GiB, root FS unchanged. **Live-verified 2026-07-05.** `DEMO-160`. |
| 5 | `nexus status kafka-east --json` | Exactly one member `role=controller-leader`; the others `controller-follower`. | stdout · the role the safety gate reads via `CanResizeVm`. `DEMO-161`. |
| 6 | `nexus scale-up kafka-east-1 --ram 6144 --yes --json` | **REFUSED, exit 2** — *"'kafka-east-1' is the current primary/leader of cluster 'kafka-east'; resizing it now would disrupt the write window. Fail over first, or pass --force-primary to override."* The VM is **not** powered off. | stdout · the cluster-safety gate refuses to power-cycle the KRaft controller-leader; the meta `kafka` adapter routed the check to the region owner by vm-name (locked by a unit test). A follower passes; `--force-primary` overrides. **Live-verified 2026-07-06.** `DEMO-161`. |
| 7 | `nexus backup restore swarm <any-id> --yes` | **REFUSED, exit 2** — *"swarm restore OVERWRITES the live Consul KV + Nomad job state in place — refused without an explicit opt-in. Re-run with --confirm-destructive …"*. | stdout · the guard fires ahead of the backup-id lookup; no cluster change. The extra opt-in prevents an accidental in-place overwrite of the live orchestration tier. `DEMO-162`. |
| 8 | `pwsh -c "$j=(nexus backup take swarm --tag restoredemo --json \| ConvertFrom-Json).backupId; nexus backup restore swarm $j --yes --confirm-destructive"` | A GREEN restore: `items restored : N` (Consul KV keys + Nomad jobs), from a freshly-taken identical snapshot. | stdout + on a manager `consul kv export \| grep -c key` matches the count. The real online restore runs `consul`/`nomad snapshot restore` against the leader once the operator opts in. **Live-verified 2026-07-06.** `DEMO-162`. |

## 5. What this proves

- **.NET engineering + architecture** — `scale-up` is one generic verb (`VmrunVmResizer`) that composes
  with the per-adapter `IClusterAdapter.CanResizeVm` gate through a small resolver (the vms.yaml→adapter
  mapping, including the documented cluster splits), rather than N per-tier resizers. The safety gates
  (`--force-primary`, `--confirm-destructive`) are explicit, unit-tested guardrails.
- **DevOps** — the day-2 operations that are easiest to get wrong (resize = power-off, restore =
  overwrite) are done inside one tool with reviewable refusals: the controller-leader gate, the
  never-repartition-a-live-boot-disk contract, and the guarded swarm restore. Honest reporting (the deb13
  root-not-last warning) beats a green checkmark that lies.
- **Advanced infra / SQL-adjacent** — the resizer's disk path understands real guest layouts (plain
  ext4 vs LVM, Windows `Resize-Partition`) and the Swarm restore round-trips Consul raft + Nomad raft
  snapshots online against the leader.
- **Python** — n/a for this infra tour (the resizer + gates are .NET/pwsh); the recording pipeline
  (VHS `.tape`) is shared with the rest of the catalog.

Full verb reference + step-by-step playbooks:
[`nexus-cli/docs/handbook.md`](https://github.com/grezap/nexus-cli/blob/main/docs/handbook.md) §1 `scale-up`
+ §3.5. Executable System B demos: `nexus-cli/docs/demos/DEMO-17`, `DEMO-160`, `DEMO-161`, `DEMO-162`.
