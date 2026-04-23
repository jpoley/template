using Microsoft.EntityFrameworkCore;
using ProjectTemplate.Domain.Entities;
using ProjectTemplate.Domain.Repositories;

namespace ProjectTemplate.Infrastructure.Relational;

public sealed class RelationalItemRepository(ItemDbContext db) : IItemRepository
{
    public async Task<Item?> GetAsync(string id, string partitionKey, CancellationToken ct = default) =>
        await db.Items.AsNoTracking()
            .FirstOrDefaultAsync(x => x.PartitionKey == partitionKey && x.Id == id, ct);

    public async Task<IReadOnlyList<Item>> ListAsync(string partitionKey, CancellationToken ct = default) =>
        await db.Items.AsNoTracking()
            .Where(x => x.PartitionKey == partitionKey)
            .OrderByDescending(x => x.CreatedAt)
            .ToListAsync(ct);

    public async Task<Item> UpsertAsync(Item item, CancellationToken ct = default)
    {
        var existing = await db.Items
            .FirstOrDefaultAsync(x => x.PartitionKey == item.PartitionKey && x.Id == item.Id, ct);

        if (existing is null)
        {
            db.Items.Add(item);
        }
        else
        {
            db.Entry(existing).CurrentValues.SetValues(item);
        }

        await db.SaveChangesAsync(ct);
        return item;
    }

    public async Task DeleteAsync(string id, string partitionKey, CancellationToken ct = default)
    {
        await db.Items
            .Where(x => x.PartitionKey == partitionKey && x.Id == id)
            .ExecuteDeleteAsync(ct);
    }
}
