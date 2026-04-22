using System.Net;
using Microsoft.Azure.Cosmos;
using Microsoft.Extensions.Logging;
using ProjectTemplate.Domain.Entities;
using ProjectTemplate.Domain.Repositories;

namespace ProjectTemplate.Infrastructure.Cosmos;

public sealed partial class CosmosItemRepository(Container container, ILogger<CosmosItemRepository> logger) : IItemRepository
{
    [LoggerMessage(Level = LogLevel.Debug, Message = "Upserted item {Id} (RU: {RequestCharge})")]
    private partial void LogUpsert(string id, double requestCharge);

    public async Task<Item?> GetAsync(string id, string partitionKey, CancellationToken ct = default)
    {
        try
        {
            var response = await container.ReadItemAsync<Item>(id, new PartitionKey(partitionKey), cancellationToken: ct);
            return response.Resource;
        }
        catch (CosmosException ex) when (ex.StatusCode == HttpStatusCode.NotFound)
        {
            return null;
        }
    }

    public async Task<IReadOnlyList<Item>> ListAsync(string partitionKey, CancellationToken ct = default)
    {
        var query = new QueryDefinition("SELECT * FROM c ORDER BY c.updatedAt DESC");
        var iterator = container.GetItemQueryIterator<Item>(
            query,
            requestOptions: new QueryRequestOptions { PartitionKey = new PartitionKey(partitionKey) });

        var results = new List<Item>();
        while (iterator.HasMoreResults)
        {
            var page = await iterator.ReadNextAsync(ct);
            results.AddRange(page);
        }
        return results;
    }

    public async Task<Item> UpsertAsync(Item item, CancellationToken ct = default)
    {
        var response = await container.UpsertItemAsync(item, new PartitionKey(item.PartitionKey), cancellationToken: ct);
        LogUpsert(item.Id, response.RequestCharge);
        return response.Resource;
    }

    public async Task DeleteAsync(string id, string partitionKey, CancellationToken ct = default)
    {
        try
        {
            await container.DeleteItemAsync<Item>(id, new PartitionKey(partitionKey), cancellationToken: ct);
        }
        catch (CosmosException ex) when (ex.StatusCode == HttpStatusCode.NotFound)
        {
            // idempotent delete
        }
    }
}
