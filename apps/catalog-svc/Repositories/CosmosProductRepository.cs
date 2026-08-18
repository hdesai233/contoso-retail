using CatalogSvc.Models;
using Microsoft.Azure.Cosmos;

namespace CatalogSvc.Repositories;

// Database/container layout per docs/02-Architecture.md §3.4: database
// `contoso-retail`, container `products` partitioned on `/categoryId`.
public class CosmosProductRepository : IProductRepository
{
    private readonly Container _container;

    public CosmosProductRepository(CosmosClient client)
    {
        _container = client.GetContainer("contoso-retail", "products");
    }

    public async Task<IReadOnlyList<Product>> GetAllAsync(CancellationToken ct = default)
    {
        var results = new List<Product>();
        using var iterator = _container.GetItemQueryIterator<Product>("SELECT * FROM c");
        while (iterator.HasMoreResults)
        {
            var page = await iterator.ReadNextAsync(ct);
            results.AddRange(page);
        }
        return results;
    }

    public async Task<Product?> GetByIdAsync(string id, CancellationToken ct = default)
    {
        // No categoryId available from the route, so this is a cross-partition
        // query rather than a point read. Fine for a catalog this size; revisit
        // if/when GetByIdAsync gains a categoryId parameter.
        var query = new QueryDefinition("SELECT * FROM c WHERE c.id = @id").WithParameter("@id", id);
        using var iterator = _container.GetItemQueryIterator<Product>(query);
        if (iterator.HasMoreResults)
        {
            var page = await iterator.ReadNextAsync(ct);
            return page.FirstOrDefault();
        }
        return null;
    }
}
