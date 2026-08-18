using CatalogSvc.Repositories;
using Xunit;

namespace CatalogSvc.Tests;

public class InMemoryProductRepositoryTests
{
    private readonly InMemoryProductRepository _repository = new();

    [Fact]
    public async Task GetAllAsync_ReturnsThreeCannedProducts()
    {
        var products = await _repository.GetAllAsync();

        Assert.Equal(3, products.Count);
    }

    [Fact]
    public async Task GetByIdAsync_KnownId_ReturnsMatchingProduct()
    {
        var product = await _repository.GetByIdAsync("1");

        Assert.NotNull(product);
        Assert.Equal("1", product!.Id);
    }

    [Fact]
    public async Task GetByIdAsync_UnknownId_ReturnsNull()
    {
        var product = await _repository.GetByIdAsync("does-not-exist");

        Assert.Null(product);
    }
}
