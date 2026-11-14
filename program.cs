
using Npgsql;

var builder = WebApplication.CreateBuilder(args);

// Read the password from the mounted Docker secret.
var password = File.ReadAllText(
    "/run/secrets/db_password").TrimEnd('\r', '\n');

// Build the PostgreSQL connection string.
var connection = new NpgsqlConnectionStringBuilder
{
    Host = "db",
    Port = 5432,
    Database = "shop",
    Username = "shop",
    Password = password
};

// Register a shared, pooled PostgreSQL data source.
builder.Services.AddSingleton<NpgsqlDataSource>(
    _ => NpgsqlDataSource.Create(connection.ConnectionString));

var app = builder.Build();

// Liveness: is the HTTP application responding?
app.MapGet("/health/live", () => "Alive");

// Readiness: can we actually query PostgreSQL?
app.MapGet("/health/ready", async (NpgsqlDataSource db) =>
{
    try
    {
        await using var cmd = db.CreateCommand("SELECT 1");
        await cmd.ExecuteScalarAsync();

        return Results.Ok("Ready");
    }
    catch
    {
        return Results.StatusCode(503);
    }
});

// Get all products.
app.MapGet("/products", async (NpgsqlDataSource db) =>
{
    var products = new List<Product>();

    await using var cmd = db.CreateCommand(
        "SELECT id, name, price FROM products ORDER BY id");

    await using var reader = await cmd.ExecuteReaderAsync();

    while (await reader.ReadAsync())
    {
        products.Add(new Product(
            reader.GetInt32(0),
            reader.GetString(1),
            reader.GetDecimal(2)));
    }

    return Results.Ok(products);
});

// Create a new product.
app.MapPost("/products", async (
    CreateProduct input,
    NpgsqlDataSource db) =>
{
    if (string.IsNullOrWhiteSpace(input.Name) ||
        input.Name.Length > 120 ||
        input.Price <= 0 ||
        input.Price > 100000)
    {
        return Results.BadRequest("Invalid product.");
    }

    var name = input.Name.Trim();

    await using var cmd = db.CreateCommand(
        """
        INSERT INTO products (name, price)
        VALUES ($1, $2)
        RETURNING id
        """);

    cmd.Parameters.Add(new NpgsqlParameter { Value = name });
    cmd.Parameters.Add(new NpgsqlParameter { Value = input.Price });

    var id = (int)(await cmd.ExecuteScalarAsync())!;

    return Results.Created(
        "/products",
        new Product(id, name, input.Price));
});


var startedAtUtc = DateTimeOffset.UtcNow;

app.MapGet("/instance", () => Results.Ok(new
{
    Instance = Environment.MachineName,
    StartedAtUtc = startedAtUtc
}));


app.MapGet("/version", () => new
{
    version = "2.0.0",
    message = "Deployed automatically with GitHub Actions!"
});


app.Run();

record Product(int Id, string Name, decimal Price);
record CreateProduct(string Name, decimal Price);

