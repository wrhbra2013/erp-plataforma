namespace MeuErp.Models;

// Mandante (Client): nível mais alto do sistema (ex: grupo empresarial).
public class Mandante
{
    public long Id { get; set; }
    public string Codigo { get; set; } = string.Empty;
    public string Nome { get; set; } = string.Empty;
    public string RazaoSocial { get; set; } = string.Empty;
    public string Cnpj { get; set; } = string.Empty;
    public string Endereco { get; set; } = string.Empty;
}
