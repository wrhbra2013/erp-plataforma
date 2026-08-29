using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using MeuErp.Database;
using MeuErpApi.Auth;
using MeuErpApi.Dtos;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.IdentityModel.Tokens;

namespace MeuErpApi.Controllers;

[ApiController]
[Route("api/[controller]")]
public class AuthController : ControllerBase
{
    [HttpPost("login")]
    public IActionResult Login([FromBody] LoginRequest req)
    {
        var usuario = DatabaseService.Autenticar(req.Login.Trim(), req.Senha);
        if (usuario == null)
            return Unauthorized(new { mensagem = "Login ou senha inválidos." });

        var claims = new List<Claim>
        {
            new(ClaimTypes.Name, usuario.Login),
            new(ClaimTypes.Role, usuario.Admin ? "Admin" : "Usuario")
        };

        var credenciais = new SigningCredentials(
            new SymmetricSecurityKey(Encoding.UTF8.GetBytes(JwtConfig.Chave)),
            SecurityAlgorithms.HmacSha256);

        var agora = DateTime.UtcNow;
        var expira = agora.AddMinutes(JwtConfig.Minutos);
        var token = new JwtSecurityToken(
            issuer: JwtConfig.Issuer,
            audience: JwtConfig.Audience,
            claims: claims,
            notBefore: agora,
            expires: expira,
            signingCredentials: credenciais);

        return Ok(new LoginResponse(
            new JwtSecurityTokenHandler().WriteToken(token),
            usuario.Nome, usuario.Login, usuario.Admin, expira));
    }

    [Authorize]
    [HttpGet("me")]
    public IActionResult Me() => Ok(new
    {
        Login = User.Identity?.Name,
        Roles = User.FindAll(ClaimTypes.Role).Select(r => r.Value)
    });
}