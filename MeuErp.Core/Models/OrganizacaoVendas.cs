namespace MeuErp.Models;

// Organização de Vendas: estrutura responsável pelas transações comerciais de saída.
public class OrganizacaoVendas
{
    public long Id { get; set; }
    public long EmpresaId { get; set; }
    public string EmpresaNome { get; set; } = string.Empty;
    public string Codigo { get; set; } = string.Empty;
    public string Nome { get; set; } = string.Empty;
    public string Moeda { get; set; } = "BRL";
}
