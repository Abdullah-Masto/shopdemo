
using Microsoft.EntityFrameworkCore;
using Npgsql;

var migrate = args.Contains("--migrate");

var builder = WebApplication.CreateBuilder(
    args.Where(arg => arg != "--migrate").ToArray());

// Read the existing Docker secret.
var password = File.ReadAllText(
    "/run/secrets/db_password").TrimEnd('\r', '\n');

var connection = new NpgsqlConnectionStringBuilder
{
    Host = "db",
    Port = 5432,
    Database = "shop",
    Username = "shop",
    Password = password
};

builder.Services.AddDbContext<ShopDbContext>(options =>
    options.UseNpgsql(connection.ConnectionString));

var app = builder.Build();

// SPECIAL MODE: apply migrations and exit.
if (migrate)
{
    await using var scope = app.Services.CreateAsyncScope();

    var db = scope.ServiceProvider
        .GetRequiredService<ShopDbContext>();

    await db.Database.MigrateAsync();

    Console.WriteLine("Database migrations completed.");

    return;
}

// NORMAL MODE: run the HTTP application.
app.MapGet("/health/live", () => "Alive");

app.MapGet("/health/ready", async (
    ShopDbContext db,
    ILogger<Program> logger) =>
{
    try
    {
        await db.Products
            .AsNoTracking()
            .Take(1)
            .ToListAsync();

        return Results.Ok("Ready");
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "Database readiness check failed.");
        return Results.StatusCode(503);
    }
});

app.MapGet("/products", async (ShopDbContext db) =>
    await db.Products
        .AsNoTracking()
        .OrderBy(p => p.Id)
        .ToListAsync());

app.MapPost("/products", async (
    CreateProduct input,
    ShopDbContext db) =>
{
    if (string.IsNullOrWhiteSpace(input.Name) ||
        input.Name.Length > 120 ||
        input.Price <= 0 ||
        input.Price > 100000)
    {
        return Results.BadRequest("Invalid product.");
    }

    var product = new Product
    {
        Name = input.Name.Trim(),
        Price = input.Price
    };

    db.Products.Add(product);

    await db.SaveChangesAsync();

    return Results.Created("/products", product);
});

var startedAtUtc = DateTimeOffset.UtcNow;

app.MapGet("/instance", () => Results.Ok(new
{
    Instance = Environment.MachineName,
    StartedAtUtc = startedAtUtc
}));

app.Run();

record CreateProduct(string Name, decimal Price);
