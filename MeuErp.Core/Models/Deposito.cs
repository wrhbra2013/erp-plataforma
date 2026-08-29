namespace MeuErp.Models;

// Depósito (Storage Location): subdivisão do centro onde o estoque físico é armazenado.
public class Deposito
{
    public long Id { get; set; }
    public long CentroId { get; set; }
    public string CentroNome { get; set; } = string.Empty;
    public string Codigo { get; set; } = string.Empty;
    public string Nome { get; set; } = string.Empty;
    public string Tipo { get; set; } = string.Empty; // Operacional, Bloqueado, Inspeção
    public string Endereco { get; set; } = string.Empty;
}
