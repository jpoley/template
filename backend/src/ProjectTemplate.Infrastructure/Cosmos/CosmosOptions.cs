namespace ProjectTemplate.Infrastructure.Cosmos;

public sealed class CosmosOptions
{
    public const string SectionName = "Cosmos";

    public string Endpoint { get; set; } = string.Empty;
    public string? Key { get; set; }
    public string DatabaseName { get; set; } = "projecttemplate";
    public string ContainerName { get; set; } = "items";
    public string PartitionKeyPath { get; set; } = "/partitionKey";
    public bool UseManagedIdentity { get; set; }
    public bool AllowBulkExecution { get; set; } = true;
}
