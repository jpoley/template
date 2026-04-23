using Azure.Identity;
using Microsoft.Azure.Cosmos;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using ProjectTemplate.Domain.Repositories;

namespace ProjectTemplate.Infrastructure.Cosmos;

public static class CosmosServiceCollectionExtensions
{
    public static IServiceCollection AddCosmos(this IServiceCollection services, IConfiguration configuration)
    {
        services.Configure<CosmosOptions>(configuration.GetSection(CosmosOptions.SectionName));

        services.AddSingleton<CosmosClient>(sp =>
        {
            var opts = sp.GetRequiredService<IOptions<CosmosOptions>>().Value;
            var clientOptions = new CosmosClientOptions
            {
                AllowBulkExecution = opts.AllowBulkExecution,
                SerializerOptions = new CosmosSerializationOptions
                {
                    PropertyNamingPolicy = CosmosPropertyNamingPolicy.CamelCase,
                },
            };

            if (opts.IsEmulator)
            {
                // Dev-only emulator handling:
                //  - Gateway mode (direct/TCP relies on replica discovery the emulator fakes)
                //  - LimitToEndpoint stops the SDK from following the emulator's advertised
                //    replica addresses (often 127.0.0.1, which inside another container
                //    resolves to itself — the classic emulator-in-docker hang).
                //  - If the endpoint is HTTPS, accept the self-signed cert.
                clientOptions.ConnectionMode = ConnectionMode.Gateway;
                clientOptions.LimitToEndpoint = true;
                if (opts.Endpoint.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
                {
                    clientOptions.HttpClientFactory = () => new HttpClient(new HttpClientHandler
                    {
                        ServerCertificateCustomValidationCallback = HttpClientHandler.DangerousAcceptAnyServerCertificateValidator,
                    });
                }
            }

            return opts.UseManagedIdentity
                ? new CosmosClient(opts.Endpoint, new DefaultAzureCredential(), clientOptions)
                : new CosmosClient(opts.Endpoint, opts.Key, clientOptions);
        });

        services.AddSingleton<Container>(sp =>
        {
            var opts = sp.GetRequiredService<IOptions<CosmosOptions>>().Value;
            var client = sp.GetRequiredService<CosmosClient>();
            return client.GetContainer(opts.DatabaseName, opts.ContainerName);
        });

        services.AddScoped<IItemRepository, CosmosItemRepository>();
        return services;
    }

    public static async Task EnsureCosmosDatabaseAsync(IServiceProvider sp, CancellationToken ct = default)
    {
        var opts = sp.GetRequiredService<IOptions<CosmosOptions>>().Value;
        var client = sp.GetRequiredService<CosmosClient>();
        var db = await client.CreateDatabaseIfNotExistsAsync(opts.DatabaseName, cancellationToken: ct);
        await db.Database.CreateContainerIfNotExistsAsync(opts.ContainerName, opts.PartitionKeyPath, cancellationToken: ct);
    }
}
