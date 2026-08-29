using MeuErp.Database;
using MeuErp.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace MeuErpApi.Controllers;

[Authorize]
[ApiController]
[Route("api/[controller]")]
public class EstoqueController : ControllerBase
{
    // LISTA o estoque geral, por produto e depósito.
    [HttpGet]
    public IActionResult Listar() => Ok(DatabaseService.ObterEstoqueGeral());

    // LISTA o estoque de um produto específico.
    [HttpGet("produto/{produtoId:long}")]
    public IActionResult PorProduto(long produtoId)
    {
        return Ok(DatabaseService.ObterEstoque(produtoId));
    }

    // GRAVA/SOBESCREVE o estoque de um produto em um depósito.
    [HttpPut]
    public IActionResult Definir([FromBody] EstoqueDeposito e)
    {
        if (e.Quantidade < 0)
            return BadRequest(new { mensagem = "Quantidade não pode ser negativa." });
        DatabaseService.DefinirEstoque(e.ProdutoId, e.DepositoId, e.Quantidade);
        return NoContent();
    }

    // MOVIMENTA o estoque (positivo ou negativo) de um produto em um depósito.
    [HttpPost("movimentar")]
    public IActionResult Movimentar([FromBody] EstoqueDeposito e)
    {
        var saldo = DatabaseService.ObterSaldo(e.ProdutoId, e.DepositoId);
        if (saldo + e.Quantidade < 0)
            return BadRequest(new { mensagem = "Estoque insuficiente no depósito." });
        DatabaseService.AtualizarEstoque(e.ProdutoId, e.DepositoId, e.Quantidade);
        return NoContent();
    }
}
