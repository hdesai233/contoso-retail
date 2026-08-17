# ADR-002: Pivot Phase 2 compute from AKS to Azure Container Apps

- **Status:** Accepted
- **Date:** 2026-08-17
- **Deciders:** you

## Context

`aks.bicep` was fully implemented per `docs/03-Implementation-Guide.md` Phase 2's original spec — Workload Identity + OIDC issuer, Application Routing add-on, Container Insights, Defender for Containers, Azure CNI Overlay with Cilium, a system pool + a user pool, AcrPull granted to the kubelet identity. Every property was verified against Microsoft Learn before deployment. It was deployed three times against `rg-contoso-dev-eus2` (eastus), in the "Azure for Students" subscription this project runs on. All three failed for reasons external to the code:

1. **`Standard_D4s_v5` / `Standard_B2s` rejected.** This subscription's allowed-VM-SKU policy only permits newer v7-generation SKUs (no B-series at all). Switched to `Standard_D4s_v7` / `Standard_D2s_v7`.
2. **`MissingSubscriptionRegistration` for `Microsoft.OperationsManagement`.** Required by the Container Insights add-on; not registered on the subscription. Registered it — a one-time, no-code fix.
3. **Stalled indefinitely.** After both fixes, the deployment sat at `provisioningState: Updating` for 50+ minutes with zero worker nodes ever provisioned, and no error surfaced. Deleted the wedged cluster and retried clean. The retry failed immediately, and this time cleanly: `ErrCode_InsufficientVCPUQuota` — *"left regional vcpu quota 6, requested quota 10."*

Digging into that error surfaced the real, unfixable-by-Bicep constraint: this subscription has a **hard cap of 6 total regional vCPUs**, and critically, that cap is **identical across every region the subscription is even allowed to deploy to** (`eastus`, `canadacentral`, `northcentralus`, `westus3`, `mexicocentral` — confirmed via `az vm list-usage` in each). AKS's system node pool has a non-negotiable Azure requirement — confirmed directly against [Microsoft Learn](https://learn.microsoft.com/azure/aks/use-system-pools#system-and-user-node-pools), not assumed — of **at least 4 vCPU per node and at least 2 nodes**, and B-series VMs aren't supported for system pools at all. That floor is 8 vCPU, before the user pool even factors in. 8 > 6, everywhere this subscription can deploy. No `aks.bicep` change — no VM size, no node count, no region — can close that gap.

(The stuck-at-`Updating` episode in attempt 3 was very likely this same quota wall, encountered mid-scale-out and surfaced as a silent hang rather than the clean error attempt 4 produced against a fresh resource — plausible but not confirmed, since the resource was deleted before that could be diagnosed further.)

## Decision

Pivot Phase 2's compute target from AKS to **Azure Container Apps (ACA), Consumption-only environment.**

This was already the project's own documented fallback — `docs/02-Architecture.md`'s cross-cutting decision table listed ACA as the alternative to AKS from the start, rejected only for pedagogical reasons ("this is a learning project that covers Kubernetes deeply, AKS is the right call... in a smaller real-world project you might pick ACA").

Before committing to it, I verified — via Microsoft Learn, not assumption, since repeating the AKS mistake with a different resource type would be worse than not pivoting — that this actually solves the problem:

- ACA's Consumption plan draws from its own environment-scoped quota (`Managed Environment Consumption Cores`), a completely separate system from the subscription's `Total Regional vCPUs` pool that blocked AKS. [Source](https://learn.microsoft.com/azure/container-apps/quotas)
- This must specifically be a **Consumption-only environment**, not a **Workload profiles environment** — the latter uses dedicated VM-backed compute and would likely hit the same VM-family quota wall. Consumption-only is the genuinely serverless option.
- Consumption-only environments require a `/23` subnet and **must not** be delegated to any service — the opposite of Workload profile environments, which need `/27` + delegation to `Microsoft.App/environments`. [Source](https://learn.microsoft.com/azure/container-apps/custom-virtual-networks)

## Consequences

- **Positive:** fits the subscription's actual quota, with no cost or capability trade-off for a project at this scale — Consumption's ~100 core/environment default quota is nowhere near a constraint for a handful of small microservices.
- **Positive:** simpler identity model. Each Container App binds its Managed Identity directly (`identity.userAssignedIdentities`) — no OIDC federated-credential step, no Kubernetes ServiceAccount to annotate.
- **Positive:** KEDA scaling is native to the Container App resource (`template.scale.rules`) — no separate `ScaledObject` manifest, and Consumption scales to zero when idle (AKS's node pools couldn't).
- **Negative:** loses the Kubernetes-specific learning objectives the project was originally designed around (cluster administration, Kustomize, node pool management, CNI internals).
- **Negative:** `k8s/base/`/`k8s/overlays/` and the Kustomize workflow in `CLAUDE.md` house rule 4 no longer apply — replaced with Bicep-defined Container Apps.
- **Neutral:** `acr.bicep` is entirely unaffected — Container Apps pulls from the same ACR via the same Managed-Identity pattern, no changes needed there.
- **Neutral:** `aks.bicep` is kept, unused, with a header comment pointing here, in case the vCPU quota is ever increased and AKS becomes viable — deleting fully-verified, working IaC over an external quota fluke felt wasteful.

## Alternatives considered

- **Request a vCPU quota increase, keep AKS.** Rejected as the immediate path — quota increase requests on capped/promotional subscriptions aren't guaranteed, and can take time to process; the user chose to pivot rather than wait. `aks.bicep` is preserved specifically so this remains available later without redoing the work.
- **Move the whole project, or just AKS, to a different (non-capped) subscription.** Not chosen — no such subscription was available at decision time.
- **Azure Container Instances (ACI) virtual nodes.** Considered and rejected quickly — even with ACI-backed virtual nodes for workload pods, AKS's system pool minimum (CoreDNS, metrics-server, etc.) still applies, so this doesn't avoid the 8 vCPU floor either.

## Addendum: VNet integration deferred (2026-08-17, same day)

The first real deployment of `container-apps-env.bicep` — Consumption-only, integrated into `snet-aca` per this ADR's own guidance — failed:

```
ManagedEnvironmentSubnetDelegationError: The subnet of the environment must
be delegated to the service 'Microsoft.App/environments'.
```

This directly contradicts [Microsoft's own documentation](https://learn.microsoft.com/azure/container-apps/custom-virtual-networks), which states Consumption-only environments must **not** be delegated (delegation is a Workload-profiles-only requirement). This is an open, unresolved platform bug — [microsoft/azure-container-apps#1644](https://github.com/microsoft/azure-container-apps/issues/1644), reported ~January 2026, no confirmed root cause or fix from Microsoft as of this writing.

Delegating the subnet to make the error go away was considered and **rejected** — it's unconfirmed whether doing so silently enrolls the environment in Workload-profiles-style dedicated compute, which would reintroduce the exact vCPU-family quota wall this entire ADR exists to route around. Deploying blind into that ambiguity risked repeating the AKS mistake with extra steps.

**Decision:** deploy `container-apps-env.bicep` **without** VNet integration (`useVnetIntegration = false`, the module's default) until there's clearer guidance. `snet-aca` stays reserved and unused in `network.bicep`. Consequence: the Container Apps environment is the one component in this project not living inside the project's own VNet — a real, if temporary, break from the private-networking-everywhere pattern used everywhere else (Key Vault, ACR, and everything still to come all sit behind Private Endpoints in `snet-pe`). Revisit once the linked GitHub issue is resolved or Microsoft Learn's guidance changes.
