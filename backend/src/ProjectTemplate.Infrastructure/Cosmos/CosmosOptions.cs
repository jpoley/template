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

    /// When true, the SDK is configured for the Linux Cosmos emulator:
    ///  - Gateway mode + LimitToEndpoint=true (avoids the emulator advertising
    ///    replicas at 127.0.0.1, which inside another container resolves to self).
    ///  - If the endpoint is HTTPS, accepts the self-signed certificate.
    /// Dev only — never enable against a real Cosmos account.
    public bool IsEmulator { get; set; }
}
