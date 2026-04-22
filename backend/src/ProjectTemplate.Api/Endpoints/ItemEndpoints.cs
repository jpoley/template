using ProjectTemplate.Domain.Entities;
using ProjectTemplate.Domain.Repositories;

namespace ProjectTemplate.Api.Endpoints;

public static class ItemEndpoints
{
    public static IEndpointRouteBuilder MapItemEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/items").WithTags("Items");

        group.MapGet("/{partitionKey}", async (string partitionKey, IItemRepository repo, CancellationToken ct) =>
            Results.Ok(await repo.ListAsync(partitionKey, ct)));

        group.MapGet("/{partitionKey}/{id}", async (string partitionKey, string id, IItemRepository repo, CancellationToken ct) =>
        {
            var item = await repo.GetAsync(id, partitionKey, ct);
            return item is null ? Results.NotFound() : Results.Ok(item);
        });

        group.MapPost("/", async (CreateItemRequest req, IItemRepository repo, CancellationToken ct) =>
        {
            var now = DateTimeOffset.UtcNow;
            var item = new Item(
                Id: Guid.NewGuid().ToString(),
                PartitionKey: req.PartitionKey,
                Name: req.Name,
                Description: req.Description,
                CreatedAt: now,
                UpdatedAt: now);
            var saved = await repo.UpsertAsync(item, ct);
            return Results.Created($"/api/items/{saved.PartitionKey}/{saved.Id}", saved);
        });

        group.MapPut("/{partitionKey}/{id}", async (string partitionKey, string id, UpdateItemRequest req, IItemRepository repo, CancellationToken ct) =>
        {
            var existing = await repo.GetAsync(id, partitionKey, ct);
            if (existing is null) return Results.NotFound();

            var updated = existing with
            {
                Name = req.Name ?? existing.Name,
                Description = req.Description ?? existing.Description,
                UpdatedAt = DateTimeOffset.UtcNow,
            };
            return Results.Ok(await repo.UpsertAsync(updated, ct));
        });

        group.MapDelete("/{partitionKey}/{id}", async (string partitionKey, string id, IItemRepository repo, CancellationToken ct) =>
        {
            await repo.DeleteAsync(id, partitionKey, ct);
            return Results.NoContent();
        });

        return app;
    }
}

public sealed record CreateItemRequest(string PartitionKey, string Name, string? Description);
public sealed record UpdateItemRequest(string? Name, string? Description);
