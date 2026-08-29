using MeuErp.Database;
using MeuErp.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace MeuErpApi.Controllers;

[Authorize]
[ApiController]
[Route("api/[controller]")]
public class EmpresasController : ControllerBase
{
    [HttpGet]
    public IActionResult Listar() => Ok(DatabaseService.ObterEmpresas());

    [HttpPost]
    public IActionResult Criar([FromBody] Empresa e)
    {
        if (string.IsNullOrWhiteSpace(e.NomeFantasia))
            return BadRequest(new { mensagem = "O campo Nome é obrigatório." });
        if (!DatabaseService.ObterMandantes().Any(m => m.Id == e.MandanteId))
            return BadRequest(new { mensagem = "Mandante inválido." });
        DatabaseService.CriarEmpresa(e);
        return Created($"/api/Empresas/{e.Id}", e);
    }

    [HttpPut("{id:long}")]
    public IActionResult Atualizar(long id, [FromBody] Empresa e)
    {
        if (string.IsNullOrWhiteSpace(e.NomeFantasia))
            return BadRequest(new { mensagem = "O campo Nome é obrigatório." });
        e.Id = id;
        DatabaseService.AtualizarEmpresa(e);
        return NoContent();
    }

    [HttpDelete("{id:long}")]
    public IActionResult Excluir(long id)
    {
        DatabaseService.ExcluirEmpresa(id);
        return NoContent();
    }
}
