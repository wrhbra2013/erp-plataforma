using MeuErp.Database;
using MeuErp.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace MeuErpApi.Controllers;

[Authorize]
[ApiController]
[Route("api/[controller]")]
public class ClientesController : ControllerBase
{
    [HttpGet]
    public IActionResult Listar() => Ok(DatabaseService.ObterClientes());

    [HttpPost]
    public IActionResult Criar([FromBody] Cliente cliente)
    {
        if (string.IsNullOrWhiteSpace(cliente.Nome))
            return BadRequest(new { mensagem = "O campo Nome é obrigatório." });
        DatabaseService.CriarCliente(cliente);
        return Created($"/api/Clientes/{cliente.Id}", cliente);
    }

    [HttpPut("{id:long}")]
    public IActionResult Atualizar(long id, [FromBody] Cliente cliente)
    {
        if (string.IsNullOrWhiteSpace(cliente.Nome))
            return BadRequest(new { mensagem = "O campo Nome é obrigatório." });
        cliente.Id = id;
        DatabaseService.AtualizarCliente(cliente);
        return NoContent();
    }

    [HttpDelete("{id:long}")]
    public IActionResult Excluir(long id)
    {
        DatabaseService.ExcluirCliente(id);
        return NoContent();
    }
}