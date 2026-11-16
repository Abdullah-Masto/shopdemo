
using Microsoft.EntityFrameworkCore;

public class Product
{
    public int Id { get; set; }
    public string Name { get; set; } = "";
    public decimal Price { get; set; }

    public int StockQuantity { get; set; }
}

public class ShopDbContext(
    DbContextOptions<ShopDbContext> options)
    : DbContext(options)
{
    public DbSet<Product> Products => Set<Product>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        var product = modelBuilder.Entity<Product>();

        product.ToTable("products", table =>
        {
            table.HasCheckConstraint(
                "products_price_check",
                "price > 0");
        });

        product.HasKey(p => p.Id)
            .HasName("products_pkey");

        product.Property(p => p.Id)
            .HasColumnName("id")
            .UseIdentityAlwaysColumn();

        product.Property(p => p.Name)
            .HasColumnName("name")
            .HasMaxLength(120)
            .IsRequired();

        product.Property(p => p.Price)
            .HasColumnName("price")
            .HasPrecision(10, 2)
            .IsRequired();

        product.Property(p => p.StockQuantity)
            .HasColumnName("stock_quantity")
            .HasDefaultValue(0)
            .IsRequired();
    }
}

