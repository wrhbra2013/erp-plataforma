using MeuErp.Database;
using MeuErp.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace MeuErpApi.Controllers;

[Authorize]
[ApiController]
[Route("api/[controller]")]
public class OrganizacoesComprasController : ControllerBase
{
    [HttpGet]
    public IActionResult Listar() => Ok(DatabaseService.ObterOrganizacoesCompras());

    [HttpPost]
    public IActionResult Criar([FromBody] OrganizacaoCompras c)
    {
        if (string.IsNullOrWhiteSpace(c.Nome))
            return BadRequest(new { mensagem = "O campo Nome é obrigatório." });
        if (!DatabaseService.ObterEmpresas().Any(e => e.Id == c.EmpresaId))
            return BadRequest(new { mensagem = "Empresa inválida." });
        DatabaseService.CriarOrganizacaoCompras(c);
        return Created($"/api/OrganizacoesCompras/{c.Id}", c);
    }

    [HttpPut("{id:long}")]
    public IActionResult Atualizar(long id, [FromBody] OrganizacaoCompras c)
    {
        if (string.IsNullOrWhiteSpace(c.Nome))
            return BadRequest(new { mensagem = "O campo Nome é obrigatório." });
        c.Id = id;
        DatabaseService.AtualizarOrganizacaoCompras(c);
        return NoContent();
    }

    [HttpDelete("{id:long}")]
    public IActionResult Excluir(long id)
    {
        DatabaseService.ExcluirOrganizacaoCompras(id);
        return NoContent();
    }
}
