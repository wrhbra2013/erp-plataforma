namespace MeuErpApi.Auth;

public static class JwtConfig
{
    public const string Issuer = "MeuErp";
    public const string Audience = "MeuErp";

    public static string Chave { get; } =
        Environment.GetEnvironmentVariable("MEUERP_JWT_KEY")
        ?? "MeuErp_Chave_JWT_Desenvolvimento_2026_0123456789abcdef";

    public const double Minutos = 480;
}