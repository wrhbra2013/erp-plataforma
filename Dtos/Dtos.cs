namespace MeuErpApi.Dtos;

public record LoginRequest(string Login, string Senha);

public record LoginResponse(string Token, string Nome, string Login, bool Admin, DateTime ExpiraEm);

public record UsuarioCriarRequest(string Nome, string Login, string Senha, bool Admin);

public record UsuarioResponse(long Id, string Nome, string Login, bool Admin);

public record PedidoItemRequest(long ProdutoId, int Quantidade);

public record PedidoCreateRequest(
    long ClienteId,
    long EmpresaId,
    long CentroId,
    long DepositoId,
    long OrganizacaoVendasId,
    List<PedidoItemRequest> Itens);

public record PedidoListaResponse(
    long Id, string ClienteNome, DateTime Data, string Status, decimal Total,
    long EmpresaId, string EmpresaNome, long CentroId, string CentroNome,
    long DepositoId, string DepositoNome, long OrganizacaoVendasId, string OrganizacaoVendasNome);

public record PedidoItemResponse(long ProdutoId, string ProdutoNome, decimal PrecoUnitario, int Quantidade, decimal Subtotal);

public record PedidoDetalheResponse(
    long Id, string ClienteNome, DateTime Data, string Status, decimal Total,
    long EmpresaId, string EmpresaNome, long CentroId, string CentroNome,
    long DepositoId, string DepositoNome, long OrganizacaoVendasId, string OrganizacaoVendasNome,
    List<PedidoItemResponse> Itens);