using MeuErp.Database;
using MeuErp.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace MeuErpApi.Controllers;

[Authorize]
[ApiController]
[Route("api/[controller]")]
public class OrganizacoesVendasController : ControllerBase
{
    [HttpGet]
    public IActionResult Listar() => Ok(DatabaseService.ObterOrganizacoesVendas());

    [HttpPost]
    public IActionResult Criar([FromBody] OrganizacaoVendas v)
    {
        if (string.IsNullOrWhiteSpace(v.Nome))
            return BadRequest(new { mensagem = "O campo Nome é obrigatório." });
        if (!DatabaseService.ObterEmpresas().Any(e => e.Id == v.EmpresaId))
            return BadRequest(new { mensagem = "Empresa inválida." });
        DatabaseService.CriarOrganizacaoVendas(v);
        return Created($"/api/OrganizacoesVendas/{v.Id}", v);
    }

    [HttpPut("{id:long}")]
    public IActionResult Atualizar(long id, [FromBody] OrganizacaoVendas v)
    {
        if (string.IsNullOrWhiteSpace(v.Nome))
            return BadRequest(new { mensagem = "O campo Nome é obrigatório." });
        v.Id = id;
        DatabaseService.AtualizarOrganizacaoVendas(v);
        return NoContent();
    }

    [HttpDelete("{id:long}")]
    public IActionResult Excluir(long id)
    {
        DatabaseService.ExcluirOrganizacaoVendas(id);
        return NoContent();
    }
}
