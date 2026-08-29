using MeuErp.Database;
using MeuErp.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace MeuErpApi.Controllers;

[Authorize]
[ApiController]
[Route("api/[controller]")]
public class DepositosController : ControllerBase
{
    [HttpGet]
    public IActionResult Listar() => Ok(DatabaseService.ObterDepositos());

    [HttpPost]
    public IActionResult Criar([FromBody] Deposito d)
    {
        if (string.IsNullOrWhiteSpace(d.Nome))
            return BadRequest(new { mensagem = "O campo Nome é obrigatório." });
        if (!DatabaseService.ObterCentros().Any(c => c.Id == d.CentroId))
            return BadRequest(new { mensagem = "Centro inválido." });
        DatabaseService.CriarDeposito(d);
        return Created($"/api/Depositos/{d.Id}", d);
    }

    [HttpPut("{id:long}")]
    public IActionResult Atualizar(long id, [FromBody] Deposito d)
    {
        if (string.IsNullOrWhiteSpace(d.Nome))
            return BadRequest(new { mensagem = "O campo Nome é obrigatório." });
        d.Id = id;
        DatabaseService.AtualizarDeposito(d);
        return NoContent();
    }

    [HttpDelete("{id:long}")]
    public IActionResult Excluir(long id)
    {
        DatabaseService.ExcluirDeposito(id);
        return NoContent();
    }
}
