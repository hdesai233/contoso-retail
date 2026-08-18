using System.Net;
using System.Net.Http.Json;
using CatalogSvc.Models;
using Microsoft.AspNetCore.Mvc.Testing;
using Xunit;

namespace CatalogSvc.Tests;

// No APPLICATIONINSIGHTS_CONNECTION_STRING / COSMOS_ENDPOINT set in the test
// environment, so Program.cs falls back to InMemoryProductRepository and
// skips OpenTelemetry — exercising the same path a fresh dev machine hits.
public class EndpointTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly HttpClient _client;

    public EndpointTests(WebApplicationFactory<Program> factory)
    {
        _client = factory.CreateClient();
    }

    [Fact]
    public async Task Healthz_ReturnsHealthy()
    {
        var response = await _client.GetAsync("/healthz");

        response.EnsureSuccessStatusCode();
        var body = await response.Content.ReadAsStringAsync();
        Assert.Contains("healthy", body);
    }

    [Fact]
    public async Task GetProducts_ReturnsThreeProducts()
    {
        var products = await _client.GetFromJsonAsync<List<Product>>("/api/products");

        Assert.NotNull(products);
        Assert.Equal(3, products!.Count);
    }

    [Fact]
    public async Task GetProductById_KnownId_ReturnsProduct()
    {
        var product = await _client.GetFromJsonAsync<Product>("/api/products/1");

        Assert.NotNull(product);
        Assert.Equal("1", product!.Id);
    }

    [Fact]
    public async Task GetProductById_UnknownId_ReturnsNotFound()
    {
        var response = await _client.GetAsync("/api/products/does-not-exist");

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }
}
