namespace MeuErp.Models;

public class Produto
{
    public long Id { get; set; }
    public string Codigo { get; set; } = string.Empty;
    public string Nome { get; set; } = string.Empty;
    public decimal Preco { get; set; }
    public decimal Custo { get; set; }
    public int Estoque { get; set; } // estoque consolidado (somatório por depósito)
}
