using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using ProjectTemplate.Domain.Repositories;

namespace ProjectTemplate.Infrastructure.Relational;

public static class RelationalServiceCollectionExtensions
{
    public static IServiceCollection AddSqlServerStore(this IServiceCollection services, IConfiguration configuration)
    {
        var cs = configuration.GetConnectionString("SqlServer")
            ?? throw new InvalidOperationException("ConnectionStrings:SqlServer is not configured.");
        services.AddDbContext<ItemDbContext>(o =>
            o.UseSqlServer(cs, sql => sql.EnableRetryOnFailure(maxRetryCount: 10, maxRetryDelay: TimeSpan.FromSeconds(5), errorNumbersToAdd: null)));
        services.AddScoped<IItemRepository, RelationalItemRepository>();
        return services;
    }

    public static IServiceCollection AddPostgresStore(this IServiceCollection services, IConfiguration configuration)
    {
        var cs = configuration.GetConnectionString("Postgres")
            ?? throw new InvalidOperationException("ConnectionStrings:Postgres is not configured.");
        services.AddDbContext<ItemDbContext>(o =>
            o.UseNpgsql(cs, npg => npg.EnableRetryOnFailure(maxRetryCount: 10, maxRetryDelay: TimeSpan.FromSeconds(5), errorCodesToAdd: null)));
        services.AddScoped<IItemRepository, RelationalItemRepository>();
        return services;
    }
}
