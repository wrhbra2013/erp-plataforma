using MeuErp.Database;
using MeuErp.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace MeuErpApi.Controllers;

[Authorize]
[ApiController]
[Route("api/[controller]")]
public class ProdutosController : ControllerBase
{
    [HttpGet]
    public IActionResult Listar() => Ok(DatabaseService.ObterProdutos());

    [HttpPost]
    public IActionResult Criar([FromBody] Produto produto)
    {
        if (string.IsNullOrWhiteSpace(produto.Nome))
            return BadRequest(new { mensagem = "O campo Nome é obrigatório." });
        if (produto.Preco < 0 || produto.Custo < 0)
            return BadRequest(new { mensagem = "Valores não podem ser negativos." });
        DatabaseService.CriarProduto(produto);
        return Created($"/api/Produtos/{produto.Id}", produto);
    }

    [HttpPut("{id:long}")]
    public IActionResult Atualizar(long id, [FromBody] Produto produto)
    {
        if (string.IsNullOrWhiteSpace(produto.Nome))
            return BadRequest(new { mensagem = "O campo Nome é obrigatório." });
        if (produto.Preco < 0 || produto.Custo < 0)
            return BadRequest(new { mensagem = "Valores não podem ser negativos." });
        produto.Id = id;
        DatabaseService.AtualizarProduto(produto);
        return NoContent();
    }

    [HttpDelete("{id:long}")]
    public IActionResult Excluir(long id)
    {
        DatabaseService.ExcluirProduto(id);
        return NoContent();
    }
}