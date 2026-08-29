namespace MeuErp.Models;

// Empresa (Company Code): unidade contábil legal (balanço e demonstrações oficiais).
public class Empresa
{
    public long Id { get; set; }
    public long MandanteId { get; set; }
    public string MandanteNome { get; set; } = string.Empty;
    public string Codigo { get; set; } = string.Empty;
    public string NomeFantasia { get; set; } = string.Empty;
    public string RazaoSocial { get; set; } = string.Empty;
    public string Cnpj { get; set; } = string.Empty;
    public string RegimeTributario { get; set; } = string.Empty;
    public string Endereco { get; set; } = string.Empty;
}
