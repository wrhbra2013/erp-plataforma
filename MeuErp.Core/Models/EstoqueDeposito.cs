namespace MeuErp.Models;

// Estoque por Depósito: quantidade física de um produto em um depósito específico.
public class EstoqueDeposito
{
    public long Id { get; set; }
    public long ProdutoId { get; set; }
    public string ProdutoNome { get; set; } = string.Empty;
    public long DepositoId { get; set; }
    public string DepositoNome { get; set; } = string.Empty;
    public long CentroId { get; set; }
    public long EmpresaId { get; set; }
    public int Quantidade { get; set; }
}
