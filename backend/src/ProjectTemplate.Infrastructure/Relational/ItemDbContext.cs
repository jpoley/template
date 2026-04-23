using Microsoft.EntityFrameworkCore;
using ProjectTemplate.Domain.Entities;

namespace ProjectTemplate.Infrastructure.Relational;

public sealed class ItemDbContext(DbContextOptions<ItemDbContext> options) : DbContext(options)
{
    public DbSet<Item> Items => Set<Item>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        var e = modelBuilder.Entity<Item>();
        e.ToTable("Items");
        e.HasKey(nameof(Item.PartitionKey), nameof(Item.Id));
        e.Property(x => x.Id).HasMaxLength(64);
        e.Property(x => x.PartitionKey).HasMaxLength(64);
        e.Property(x => x.Name).HasMaxLength(256);
        e.Property(x => x.Description).HasMaxLength(2048);
        e.Property(x => x.CreatedAt);
        e.Property(x => x.UpdatedAt);
        e.HasIndex(x => x.PartitionKey);
    }
}
