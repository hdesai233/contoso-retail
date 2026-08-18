using CatalogSvc.Models;

namespace CatalogSvc.Repositories;

public interface IProductRepository
{
    Task<IReadOnlyList<Product>> GetAllAsync(CancellationToken ct = default);

    Task<Product?> GetByIdAsync(string id, CancellationToken ct = default);
}
