using MeuErp.Database;
using MeuErp.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace MeuErpApi.Controllers;

[Authorize]
[ApiController]
[Route("api/[controller]")]
public class CentrosController : ControllerBase
{
    [HttpGet]
    public IActionResult Listar() => Ok(DatabaseService.ObterCentros());

    [HttpPost]
    public IActionResult Criar([FromBody] Centro c)
    {
        if (string.IsNullOrWhiteSpace(c.Nome))
            return BadRequest(new { mensagem = "O campo Nome é obrigatório." });
        if (!DatabaseService.ObterEmpresas().Any(e => e.Id == c.EmpresaId))
            return BadRequest(new { mensagem = "Empresa inválida." });
        DatabaseService.CriarCentro(c);
        return Created($"/api/Centros/{c.Id}", c);
    }

    [HttpPut("{id:long}")]
    public IActionResult Atualizar(long id, [FromBody] Centro c)
    {
        if (string.IsNullOrWhiteSpace(c.Nome))
            return BadRequest(new { mensagem = "O campo Nome é obrigatório." });
        c.Id = id;
        DatabaseService.AtualizarCentro(c);
        return NoContent();
    }

    [HttpDelete("{id:long}")]
    public IActionResult Excluir(long id)
    {
        DatabaseService.ExcluirCentro(id);
        return NoContent();
    }
}
