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
}
