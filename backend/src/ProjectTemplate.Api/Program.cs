using ProjectTemplate.Api.Endpoints;
using ProjectTemplate.Infrastructure.Cosmos;
using ProjectTemplate.Infrastructure.InMemory;
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

var cosmosEndpoint = builder.Configuration["Cosmos:Endpoint"];
if (string.IsNullOrWhiteSpace(cosmosEndpoint))
{
    builder.Services.AddInMemoryStore();
    Console.WriteLine("[startup] Cosmos:Endpoint empty — using in-memory store. Data will not persist.");
}
else
{
    builder.Services.AddCosmos(builder.Configuration);
}

var app = builder.Build();

app.UseSerilogRequestLogging();
app.UseExceptionHandler();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
    app.MapScalarApiReference();
}

app.UseCors();

app.MapHealthChecks("/api/health");
app.MapItemEndpoints();

app.Run();

public partial class Program;
