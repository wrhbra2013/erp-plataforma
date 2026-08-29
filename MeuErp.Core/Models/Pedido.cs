namespace MeuErp.Models;

public class Pedido
{
    public long Id { get; set; }
    public long ClienteId { get; set; }
    public string ClienteNome { get; set; } = string.Empty;

    // Estrutura organizacional da venda
    public long EmpresaId { get; set; }
    public string EmpresaNome { get; set; } = string.Empty;
    public long CentroId { get; set; }
    public string CentroNome { get; set; } = string.Empty;
    public long DepositoId { get; set; }
    public string DepositoNome { get; set; } = string.Empty;
    public long OrganizacaoVendasId { get; set; }
    public string OrganizacaoVendasNome { get; set; } = string.Empty;

    public DateTime Data { get; set; } = DateTime.Now;
    public string Status { get; set; } = "Aberto";

    public List<PedidoItem> Itens { get; set; } = new();

    public decimal Total => Itens.Sum(i => i.Subtotal);
}

public class PedidoItem
{
    public long Id { get; set; }
    public long PedidoId { get; set; }
    public long ProdutoId { get; set; }
    public string ProdutoNome { get; set; } = string.Empty;
    public decimal PrecoUnitario { get; set; }
    public int Quantidade { get; set; }

    public decimal Subtotal => PrecoUnitario * Quantidade;
}
