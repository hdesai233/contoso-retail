using CatalogSvc.Models;

namespace CatalogSvc.Repositories;

// Used until COSMOS_ENDPOINT is configured (Phase 3) — see docs/03-Implementation-Guide.md Phase 2.
public class InMemoryProductRepository : IProductRepository
{
    private static readonly IReadOnlyList<Product> Products =
    [
        new Product("1", "outdoor", "Trail Running Shoes", "Lightweight shoes built for uneven terrain.", 89.99m),
        new Product("2", "outdoor", "2-Person Tent", "Weatherproof tent with a 10-minute setup.", 149.99m),
        new Product("3", "kitchen", "Insulated Travel Mug", "Keeps drinks hot or cold for 12 hours.", 24.99m)
    ];

    public Task<IReadOnlyList<Product>> GetAllAsync(CancellationToken ct = default)
        => Task.FromResult(Products);

    public Task<Product?> GetByIdAsync(string id, CancellationToken ct = default)
        => Task.FromResult(Products.FirstOrDefault(p => p.Id == id));
}
