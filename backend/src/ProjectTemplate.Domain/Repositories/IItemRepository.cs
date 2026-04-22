using ProjectTemplate.Domain.Entities;

namespace ProjectTemplate.Domain.Repositories;

public interface IItemRepository
{
    Task<Item?> GetAsync(string id, string partitionKey, CancellationToken ct = default);
    Task<IReadOnlyList<Item>> ListAsync(string partitionKey, CancellationToken ct = default);
    Task<Item> UpsertAsync(Item item, CancellationToken ct = default);
    Task DeleteAsync(string id, string partitionKey, CancellationToken ct = default);
}
