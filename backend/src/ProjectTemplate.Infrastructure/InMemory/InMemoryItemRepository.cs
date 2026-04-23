using System.Collections.Concurrent;
using ProjectTemplate.Domain.Entities;
using ProjectTemplate.Domain.Repositories;

namespace ProjectTemplate.Infrastructure.InMemory;

/// <summary>
/// Thread-safe in-memory store. Used when no connection string is configured
/// (e.g. "bun run dev" against "dotnet run" with no backing database).
/// Not suitable for production — data vanishes on restart.
/// </summary>
public sealed class InMemoryItemRepository : IItemRepository
{
    private readonly ConcurrentDictionary<string, Item> _store = new();

    private static string Key(string partitionKey, string id) => $"{partitionKey}::{id}";

    public Task<Item?> GetAsync(string id, string partitionKey, CancellationToken ct = default)
    {
        _store.TryGetValue(Key(partitionKey, id), out var item);
        return Task.FromResult(item);
    }

    public Task<IReadOnlyList<Item>> ListAsync(string partitionKey, CancellationToken ct = default)
    {
        IReadOnlyList<Item> items = _store.Values
            .Where(i => i.PartitionKey == partitionKey)
            .OrderByDescending(i => i.UpdatedAt)
            .ToList();
        return Task.FromResult(items);
    }

    public Task<Item> UpsertAsync(Item item, CancellationToken ct = default)
    {
        _store[Key(item.PartitionKey, item.Id)] = item;
        return Task.FromResult(item);
    }

    public Task DeleteAsync(string id, string partitionKey, CancellationToken ct = default)
    {
        _store.TryRemove(Key(partitionKey, id), out _);
        return Task.CompletedTask;
    }
}
