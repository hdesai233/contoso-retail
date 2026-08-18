using Azure.Identity;
using Azure.Monitor.OpenTelemetry.AspNetCore;
using CatalogSvc.Repositories;
using Microsoft.Azure.Cosmos;
using OpenTelemetry.Resources;

var builder = WebApplication.CreateBuilder(args);

// Structured JSON logging — never Console.WriteLine, per CLAUDE.md house rule 6.
builder.Logging.ClearProviders();
builder.Logging.AddJsonConsole();

// OpenTelemetry → Azure Monitor. UseAzureMonitor() reads
// APPLICATIONINSIGHTS_CONNECTION_STRING itself; skip entirely rather than let
// it start against an empty connection string during local inner-loop dev.
var appInsightsConnectionString = builder.Configuration["APPLICATIONINSIGHTS_CONNECTION_STRING"];
if (!string.IsNullOrWhiteSpace(appInsightsConnectionString))
{
    builder.Services.AddOpenTelemetry()
        .ConfigureResource(r => r.AddService("catalog-svc"))
        .UseAzureMonitor();
}

// Cosmos is optional until Phase 3 — fall back to canned in-memory data so
// this service is useful (and testable) standalone. DefaultAzureCredential
// only: no connection strings, no keys, per CLAUDE.md house rule 1.
var cosmosEndpoint = builder.Configuration["COSMOS_ENDPOINT"];
if (!string.IsNullOrWhiteSpace(cosmosEndpoint))
{
    builder.Services.AddSingleton(_ => new CosmosClient(cosmosEndpoint, new DefaultAzureCredential()));
    builder.Services.AddSingleton<IProductRepository, CosmosProductRepository>();
}
else
{
    builder.Services.AddSingleton<IProductRepository, InMemoryProductRepository>();
}

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

// No UseHttpsRedirection(): Container Apps terminates TLS at its own edge
// and forwards plain HTTP to the container internally, so the app itself
// never sees an HTTPS request to redirect from or to — the middleware just
// logs "Failed to determine the https port for redirect" on every request.

app.MapGet("/healthz", () => Results.Ok(new { status = "healthy" }))
    .WithName("HealthCheck");

app.MapGet("/api/products", async (IProductRepository repo, CancellationToken ct) =>
        Results.Ok(await repo.GetAllAsync(ct)))
    .WithName("GetProducts");

app.MapGet("/api/products/{id}", async (string id, IProductRepository repo, CancellationToken ct) =>
    {
        var product = await repo.GetByIdAsync(id, ct);
        return product is not null ? Results.Ok(product) : Results.NotFound();
    })
    .WithName("GetProductById");

app.Run();

// Exposes the generated Program class to catalog-svc.Tests via WebApplicationFactory<Program>.
public partial class Program { }
