using MeuErp.Database;
using MeuErp.Models;
using MeuErpApi.Dtos;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace MeuErpApi.Controllers;

[Authorize(Roles = "Admin")]
[ApiController]
[Route("api/[controller]")]
public class UsuariosController : ControllerBase
{
    [HttpGet]
    public IActionResult Listar() => Ok(DatabaseService.ObterUsuarios()
        .Select(u => new UsuarioResponse(u.Id, u.Nome, u.Login, u.Admin)));

    [HttpPost]
    public IActionResult Criar([FromBody] UsuarioCriarRequest req)
    {
        if (string.IsNullOrWhiteSpace(req.Nome) || string.IsNullOrWhiteSpace(req.Login))
            return BadRequest(new { mensagem = "Nome e Login são obrigatórios." });
        if (string.IsNullOrWhiteSpace(req.Senha) || req.Senha.Length < 4)
            return BadRequest(new { mensagem = "A senha deve ter ao menos 4 caracteres." });
        if (DatabaseService.ObterUsuarios().Any(u => u.Login.Equals(req.Login.Trim(), StringComparison.OrdinalIgnoreCase)))
            return Conflict(new { mensagem = "Já existe um usuário com esse login." });

        var usuario = new Usuario { Nome = req.Nome.Trim(), Login = req.Login.Trim(), Senha = req.Senha, Admin = req.Admin };
        DatabaseService.CriarUsuario(usuario);
        return Created($"/api/Usuarios/{usuario.Id}", new UsuarioResponse(usuario.Id, usuario.Nome, usuario.Login, usuario.Admin));
    }

    [HttpDelete("{id:long}")]
    public IActionResult Excluir(long id)
    {
        var usuario = DatabaseService.ObterUsuarios().FirstOrDefault(u => u.Id == id);
        if (usuario == null)
            return NotFound();
        if (usuario.Admin)
            return BadRequest(new { mensagem = "Não é possível excluir um usuário administrador." });
        DatabaseService.ExcluirUsuario(id);
        return NoContent();
    }
}