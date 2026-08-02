// purview.bicep — Phase 5
// Purview account; registers Cosmos, SQL, ADLS, Synapse as data sources.
//
// See docs/03-Implementation-Guide.md Phase 5 for the full spec and Claude Code
// prompt for generating this module.
//
// TODO: implement this module.

targetScope = 'resourceGroup'

@description('Short workload name, e.g. contoso')
param workload string

@allowed(['dev', 'test', 'prod'])
param env string

@description('Location for the resource(s)')
param location string = resourceGroup().location

@description('Tags applied to all resources')
param tags object = {}

// TODO: additional parameters (subnet IDs, private DNS zone IDs, LA workspace ID, etc.)

// TODO: resource declarations

// TODO: outputs
