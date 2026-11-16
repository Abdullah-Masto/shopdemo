
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

public class ShopDbContextFactory
    : IDesignTimeDbContextFactory<ShopDbContext>
{
    public ShopDbContext CreateDbContext(string[] args)
    {
        var options = new DbContextOptionsBuilder<ShopDbContext>();

        options.UseNpgsql(
            "Host=localhost;Database=shop;Username=shop;" +
            "Password=design-time-placeholder");

        return new ShopDbContext(options.Options);
    }
}

