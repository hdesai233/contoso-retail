# ADR-001: Dev environment deploys to East US, not East US 2

- **Status:** Accepted
- **Date:** 2026-08-02
- **Deciders:** you

## Context

`docs/naming.md` and every `infra/env/*.bicepparam` file were written assuming
a single region, East US 2 (`eus2`), across all three environments.

While validating `infra/modules/network.bicep` with `az deployment group
what-if` against `rg-contoso-dev-eus2` in the "Azure for Students" subscription
(tenant `m365.psu.edu`), every resource was rejected:

```
RequestDisallowedByAzure - Resource 'vnet-contoso-dev-eus2' was disallowed by
Azure: This policy maintains a set of best available regions where your
subscription can deploy resources...
```

The subscription has a built-in **"Allowed resource deployment regions"**
policy assignment (`sys.regionrestriction`) — almost certainly set at the
Penn State tenant/management-group level, not something this project
controls. Its allowed list is:

```
mexicocentral, canadacentral, eastus, northcentralus, westus3
```

`eastus2` is not on it. `eastus` is, and is the closest match to the
project's original choice.

Note: the resource group `rg-contoso-dev-eus2` itself already exists *in*
`eastus2` — resource groups aren't restricted by this policy, only the
resources deployed into them. So the RG name and location stay as-is; only
the region *resources are deployed to* changes.

## Decision

The **dev** environment deploys to **East US** (`eastus`, abbreviation `eus`)
instead of East US 2. `infra/env/dev.bicepparam` now sets `location =
'eastus'` and `regionAbbr = 'eus'` explicitly (previously `location` was
commented out and implicitly resolved to the resource group's own region).

`main.bicep` gained a `regionAbbr` param (previously a hardcoded var) so each
environment can carry its own region abbreviation without the naming
convention drifting from the actual deployment region.

Test and prod remain targeted at East US 2 per the original convention —
**unchanged, not verified**. Their subscriptions may or may not carry the
same policy; confirm before the first deployment to either.

## Consequences

- Positive: dev deployments actually succeed under the current subscription
  policy.
- Positive: region is now an explicit, per-environment param instead of an
  assumption baked into a shared default — the same module set can serve
  environments in different regions without code changes.
- Negative: dev resource **names** contain `eus` while the dev resource
  **group** name still contains `eus2` (`rg-contoso-dev-eus2`) — a visible
  inconsistency. Renaming/recreating the resource group was judged more
  disruptive than the inconsistency itself; revisit if it causes confusion.
- Negative: `docs/naming.md`'s per-resource-type tables need their dev-column
  examples corrected from `-eus2`/`eus2` to `-eus`/`eus` (follow-up).
- Neutral: test/prod naming and region assumptions are unverified against
  their own (not-yet-provisioned) subscriptions.

## Alternatives considered

- **Request a policy exception for eastus2.** Rejected for now — it's a
  tenant-level policy on a student subscription; not worth the overhead for
  a learning project when eastus is an equally reasonable region.
- **Deploy to eastus but keep names saying `eus2`.** Rejected — actively
  misleading; a resource's name is supposed to tell you where it lives.
- **Recreate `rg-contoso-dev-eus2` as `rg-contoso-dev-eus`.** Deferred — the
  RG already exists and isn't itself blocked by the policy; recreating it is
  a destructive action with no functional benefit right now.
