namespace ProjectTemplate.Domain.Entities;

public sealed record Item(
    string Id,
    string PartitionKey,
    string Name,
    string? Description,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt);
