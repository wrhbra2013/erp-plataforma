using MeuErp.Database;
using MeuErp.Models;
using MeuErpApi.Dtos;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace MeuErpApi.Controllers;

[Authorize]
[ApiController]
[Route("api/[controller]")]
public class PedidosController : ControllerBase
{
    [HttpGet]
    public IActionResult Listar()
    {
        var lista = new List<PedidoListaResponse>();
        foreach (var p in DatabaseService.ObterPedidos())
        {
            var itens = DatabaseService.ObterItens(p.Id);
            lista.Add(new PedidoListaResponse(
                p.Id, p.ClienteNome, p.Data, p.Status, itens.Sum(i => i.Subtotal),
                p.EmpresaId, p.EmpresaNome, p.CentroId, p.CentroNome,
                p.DepositoId, p.DepositoNome, p.OrganizacaoVendasId, p.OrganizacaoVendasNome));
        }
        return Ok(lista);
    }

    [HttpGet("{id:long}")]
    public IActionResult Detalhe(long id)
    {
        var pedido = DatabaseService.ObterPedidos().FirstOrDefault(p => p.Id == id);
        if (pedido == null)
            return NotFound();
        var itens = DatabaseService.ObterItens(id).Select(i =>
            new PedidoItemResponse(i.ProdutoId, i.ProdutoNome, i.PrecoUnitario, i.Quantidade, i.Subtotal));
        return Ok(new PedidoDetalheResponse(
            pedido.Id, pedido.ClienteNome, pedido.Data, pedido.Status,
            itens.Sum(i => i.Subtotal),
            pedido.EmpresaId, pedido.EmpresaNome,
            pedido.CentroId, pedido.CentroNome,
            pedido.DepositoId, pedido.DepositoNome,
            pedido.OrganizacaoVendasId, pedido.OrganizacaoVendasNome,
            itens.ToList()));
    }

    [HttpPost]
    public IActionResult Criar([FromBody] PedidoCreateRequest req)
    {
        if (req.Itens == null || req.Itens.Count == 0)
            return BadRequest(new { mensagem = "O pedido deve ter ao menos um item." });

        if (req.DepositoId <= 0)
            return BadRequest(new { mensagem = "Selecione o depósito de saída." });
        if (DatabaseService.ObterDepositos().All(d => d.Id != req.DepositoId))
            return BadRequest(new { mensagem = "Depósito inexistente." });

        var produtoIds = req.Itens.Select(i => i.ProdutoId).ToHashSet();
        var produtos = DatabaseService.ObterProdutos().Where(p => produtoIds.Contains(p.Id)).ToDictionary(p => p.Id);

        for (var itemIndex = 0; itemIndex < req.Itens.Count; itemIndex++)
        {
            var item = req.Itens[itemIndex];
            if (!produtos.TryGetValue(item.ProdutoId, out var produto))
                return BadRequest(new { mensagem = $"Produto {item.ProdutoId} inexistente." });
            if (item.Quantidade <= 0)
                return BadRequest(new { mensagem = "Quantidade deve ser maior que zero." });
            var saldo = DatabaseService.ObterSaldo(item.ProdutoId, req.DepositoId);
            if (item.Quantidade > saldo)
                return BadRequest(new { mensagem = $"Estoque insuficiente de '{produto.Nome}' no depósito (disponível: {saldo})." });
        }

        var pedido = new Pedido
        {
            ClienteId = req.ClienteId,
            EmpresaId = req.EmpresaId,
            CentroId = req.CentroId,
            DepositoId = req.DepositoId,
            OrganizacaoVendasId = req.OrganizacaoVendasId,
            Status = "Fechado"
        };
        foreach (var item in req.Itens)
        {
            pedido.Itens.Add(new PedidoItem
            {
                ProdutoId = item.ProdutoId,
                ProdutoNome = produtos[item.ProdutoId].Nome,
                PrecoUnitario = produtos[item.ProdutoId].Preco,
                Quantidade = item.Quantidade
            });
            DatabaseService.AtualizarEstoque(item.ProdutoId, req.DepositoId, -item.Quantidade);
        }

        try
        {
            DatabaseService.CriarPedido(pedido);
        }
        catch
        {
            return BadRequest(new { mensagem = "Falha ao criar o pedido. Verifique o ClienteId." });
        }
        return Created($"/api/Pedidos/{pedido.Id}", pedido);
    }

    [HttpDelete("{id:long}")]
    public IActionResult Excluir(long id)
    {
        DatabaseService.ExcluirPedido(id);
        return NoContent();
    }
}
