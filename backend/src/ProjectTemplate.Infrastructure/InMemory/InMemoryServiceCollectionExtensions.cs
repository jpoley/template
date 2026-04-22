using Microsoft.Extensions.DependencyInjection;
using ProjectTemplate.Domain.Repositories;

namespace ProjectTemplate.Infrastructure.InMemory;

public static class InMemoryServiceCollectionExtensions
{
    public static IServiceCollection AddInMemoryStore(this IServiceCollection services)
    {
        services.AddSingleton<IItemRepository, InMemoryItemRepository>();
        return services;
    }
}
