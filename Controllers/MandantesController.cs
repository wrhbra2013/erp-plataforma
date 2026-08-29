using MeuErp.Database;
using MeuErp.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace MeuErpApi.Controllers;

[Authorize]
[ApiController]
[Route("api/[controller]")]
public class MandantesController : ControllerBase
{
    [HttpGet]
    public IActionResult Listar() => Ok(DatabaseService.ObterMandantes());

    [HttpPost]
    public IActionResult Criar([FromBody] Mandante m)
    {
        if (string.IsNullOrWhiteSpace(m.Nome))
            return BadRequest(new { mensagem = "O campo Nome é obrigatório." });
        DatabaseService.CriarMandante(m);
        return Created($"/api/Mandantes/{m.Id}", m);
    }

    [HttpPut("{id:long}")]
    public IActionResult Atualizar(long id, [FromBody] Mandante m)
    {
        if (string.IsNullOrWhiteSpace(m.Nome))
            return BadRequest(new { mensagem = "O campo Nome é obrigatório." });
        m.Id = id;
        DatabaseService.AtualizarMandante(m);
        return NoContent();
    }

    [HttpDelete("{id:long}")]
    public IActionResult Excluir(long id)
    {
        DatabaseService.ExcluirMandante(id);
        return NoContent();
    }
}
