namespace MeuErp.Models;

// Centro (Plant): onde a operação acontece (fábricas, CDs ou sedes).
public class Centro
{
    public long Id { get; set; }
    public long EmpresaId { get; set; }
    public string EmpresaNome { get; set; } = string.Empty;
    public string Codigo { get; set; } = string.Empty;
    public string Nome { get; set; } = string.Empty;
    public string Tipo { get; set; } = string.Empty; // Fabrica, CD, Sede
    public string Endereco { get; set; } = string.Empty;
}
