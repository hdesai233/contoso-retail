namespace CatalogSvc.Models;

public record Product(string Id, string CategoryId, string Name, string Description, decimal Price);
