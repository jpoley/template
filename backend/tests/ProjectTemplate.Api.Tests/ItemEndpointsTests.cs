using System.Net;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Shouldly;
using Xunit;

namespace ProjectTemplate.Api.Tests;

public sealed class InMemoryWebApplicationFactory : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseSetting("Database:Provider", "InMemory");
        builder.ConfigureAppConfiguration((_, cfg) =>
            cfg.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Database:Provider"] = "InMemory",
            }));
    }
}

public sealed class ItemEndpointsTests : IClassFixture<InMemoryWebApplicationFactory>
{
    private readonly HttpClient _client;

    public ItemEndpointsTests(InMemoryWebApplicationFactory factory) => _client = factory.CreateClient();

    [Fact]
    public async Task Post_creates_item_and_returns_location()
    {
        var response = await _client.PostAsJsonAsync("/api/items/", new { partitionKey = "pk-1", name = "one", description = "first" });

        response.StatusCode.ShouldBe(HttpStatusCode.Created);
        response.Headers.Location.ShouldNotBeNull();
        var created = await response.Content.ReadFromJsonAsync<ItemDto>();
        created.ShouldNotBeNull();
        created.Id.ShouldNotBeNullOrWhiteSpace();
        created.Name.ShouldBe("one");
        created.PartitionKey.ShouldBe("pk-1");
    }

    [Fact]
    public async Task Get_list_returns_created_items_for_partition()
    {
        var pk = $"pk-list-{Guid.NewGuid():N}";
        await _client.PostAsJsonAsync("/api/items/", new { partitionKey = pk, name = "a", description = (string?)null });
        await _client.PostAsJsonAsync("/api/items/", new { partitionKey = pk, name = "b", description = (string?)null });

        var items = await _client.GetFromJsonAsync<List<ItemDto>>($"/api/items/{pk}");

        items.ShouldNotBeNull();
        items.Count.ShouldBe(2);
        items.Select(i => i.Name).ShouldBe(new[] { "a", "b" }, ignoreOrder: true);
    }

    [Fact]
    public async Task Get_single_returns_404_when_missing()
    {
        var response = await _client.GetAsync($"/api/items/nope/{Guid.NewGuid()}");
        response.StatusCode.ShouldBe(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task Get_single_returns_created_item()
    {
        var pk = $"pk-get-{Guid.NewGuid():N}";
        var created = await CreateItem(pk, "target", "desc");

        var fetched = await _client.GetFromJsonAsync<ItemDto>($"/api/items/{pk}/{created.Id}");

        fetched.ShouldNotBeNull();
        fetched.Id.ShouldBe(created.Id);
        fetched.Name.ShouldBe("target");
    }

    [Fact]
    public async Task Put_updates_name_and_preserves_id()
    {
        var pk = $"pk-put-{Guid.NewGuid():N}";
        var created = await CreateItem(pk, "before", null);

        var response = await _client.PutAsJsonAsync($"/api/items/{pk}/{created.Id}",
            new { name = "after", description = (string?)null });

        response.StatusCode.ShouldBe(HttpStatusCode.OK);
        var updated = await response.Content.ReadFromJsonAsync<ItemDto>();
        updated.ShouldNotBeNull();
        updated.Id.ShouldBe(created.Id);
        updated.Name.ShouldBe("after");
    }

    [Fact]
    public async Task Put_returns_404_when_item_missing()
    {
        var response = await _client.PutAsJsonAsync($"/api/items/nope/{Guid.NewGuid()}",
            new { name = "x", description = (string?)null });
        response.StatusCode.ShouldBe(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task Delete_removes_item_and_subsequent_get_returns_404()
    {
        var pk = $"pk-del-{Guid.NewGuid():N}";
        var created = await CreateItem(pk, "doomed", null);

        var del = await _client.DeleteAsync($"/api/items/{pk}/{created.Id}");
        del.StatusCode.ShouldBe(HttpStatusCode.NoContent);

        var get = await _client.GetAsync($"/api/items/{pk}/{created.Id}");
        get.StatusCode.ShouldBe(HttpStatusCode.NotFound);
    }

    private async Task<ItemDto> CreateItem(string partitionKey, string name, string? description)
    {
        var response = await _client.PostAsJsonAsync("/api/items/",
            new { partitionKey, name, description });
        response.EnsureSuccessStatusCode();
        var item = await response.Content.ReadFromJsonAsync<ItemDto>();
        item.ShouldNotBeNull();
        return item;
    }

    private sealed record ItemDto(string Id, string PartitionKey, string Name, string? Description);
}
