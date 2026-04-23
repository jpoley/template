using Microsoft.EntityFrameworkCore;
using ProjectTemplate.Api.Endpoints;
using ProjectTemplate.Infrastructure.Cosmos;
using ProjectTemplate.Infrastructure.InMemory;
using ProjectTemplate.Infrastructure.Relational;
using Scalar.AspNetCore;
using Serilog;

var builder = WebApplication.CreateBuilder(args);

builder.Host.UseSerilog((ctx, cfg) => cfg
    .ReadFrom.Configuration(ctx.Configuration)
    .Enrich.FromLogContext()
    .WriteTo.Console());

builder.Services.AddOpenApi();
builder.Services.AddProblemDetails();
builder.Services.AddHealthChecks();

builder.Services.AddCors(options =>
{
    var origins = builder.Configuration.GetSection("Cors:Origins").Get<string[]>() ?? [];
    options.AddDefaultPolicy(policy =>
        policy.WithOrigins(origins).AllowAnyHeader().AllowAnyMethod());
});

var provider = (builder.Configuration["Database:Provider"] ?? "Cosmos").Trim();
Console.WriteLine($"[startup] Database:Provider = {provider}");

switch (provider.ToLowerInvariant())
{
    case "inmemory":
        builder.Services.AddInMemoryStore();
        break;
    case "sqlserver":
        builder.Services.AddSqlServerStore(builder.Configuration);
        break;
    case "postgres":
    case "postgresql":
        builder.Services.AddPostgresStore(builder.Configuration);
        break;
    case "cosmos":
        if (string.IsNullOrWhiteSpace(builder.Configuration["Cosmos:Endpoint"]))
        {
            builder.Services.AddInMemoryStore();
            Console.WriteLine("[startup] Cosmos:Endpoint empty — falling back to in-memory store.");
        }
        else
        {
            builder.Services.AddCosmos(builder.Configuration);
        }
        break;
    default:
        throw new InvalidOperationException(
            $"Unknown Database:Provider '{provider}'. Expected Cosmos, SqlServer, Postgres, or InMemory.");
}

var app = builder.Build();

app.UseSerilogRequestLogging();
app.UseExceptionHandler();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
    app.MapScalarApiReference();

    // Provision schema on startup for dev ergonomics. Migrations stay the prod path.
    await using var scope = app.Services.CreateAsyncScope();
    switch (provider.ToLowerInvariant())
    {
        case "sqlserver":
        case "postgres":
        case "postgresql":
            await scope.ServiceProvider.GetRequiredService<ItemDbContext>().Database.EnsureCreatedAsync();
            break;
        case "cosmos" when !string.IsNullOrWhiteSpace(builder.Configuration["Cosmos:Endpoint"]):
            await CosmosServiceCollectionExtensions.EnsureCosmosDatabaseAsync(scope.ServiceProvider);
            break;
    }
}

app.UseCors();

app.MapHealthChecks("/api/health");
app.MapItemEndpoints();

app.Run();

public partial class Program;
