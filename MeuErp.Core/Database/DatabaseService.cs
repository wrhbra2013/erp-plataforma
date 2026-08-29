using Microsoft.Data.Sqlite;
using MeuErp.Models;
using System.Security.Cryptography;
using System.Text;

namespace MeuErp.Database;

public static class DatabaseService
{
    public static string DbPath { get; } = Environment.GetEnvironmentVariable("MEUERP_DB")
        ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "MeuErp", "erp.db");

    public static void Inicializar()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(DbPath)!);
        using var cmd = CriarComando();
        cmd.CommandText = """
            CREATE TABLE IF NOT EXISTS Usuarios (
                Id INTEGER PRIMARY KEY AUTOINCREMENT,
                Nome TEXT NOT NULL,
                Login TEXT NOT NULL UNIQUE,
                Senha TEXT NOT NULL,
                Admin INTEGER NOT NULL DEFAULT 0
            );

            -- ---------- Estrutura Organizacional ----------
            CREATE TABLE IF NOT EXISTS Mandantes (
                Id INTEGER PRIMARY KEY AUTOINCREMENT,
                Codigo TEXT UNIQUE,
                Nome TEXT NOT NULL,
                RazaoSocial TEXT,
                Cnpj TEXT,
                Endereco TEXT
            );
            CREATE TABLE IF NOT EXISTS Empresas (
                Id INTEGER PRIMARY KEY AUTOINCREMENT,
                MandanteId INTEGER NOT NULL,
                Codigo TEXT UNIQUE,
                NomeFantasia TEXT NOT NULL,
                RazaoSocial TEXT,
                Cnpj TEXT,
                RegimeTributario TEXT,
                Endereco TEXT,
                FOREIGN KEY(MandanteId) REFERENCES Mandantes(Id)
            );
            CREATE TABLE IF NOT EXISTS Centros (
                Id INTEGER PRIMARY KEY AUTOINCREMENT,
                EmpresaId INTEGER NOT NULL,
                Codigo TEXT UNIQUE,
                Nome TEXT NOT NULL,
                Tipo TEXT,
                Endereco TEXT,
                FOREIGN KEY(EmpresaId) REFERENCES Empresas(Id)
            );
            CREATE TABLE IF NOT EXISTS Depositos (
                Id INTEGER PRIMARY KEY AUTOINCREMENT,
                CentroId INTEGER NOT NULL,
                Codigo TEXT UNIQUE,
                Nome TEXT NOT NULL,
                Tipo TEXT,
                Endereco TEXT,
                FOREIGN KEY(CentroId) REFERENCES Centros(Id)
            );
            CREATE TABLE IF NOT EXISTS OrganizacoesVendas (
                Id INTEGER PRIMARY KEY AUTOINCREMENT,
                EmpresaId INTEGER NOT NULL,
                Codigo TEXT UNIQUE,
                Nome TEXT NOT NULL,
                Moeda TEXT NOT NULL DEFAULT 'BRL',
                FOREIGN KEY(EmpresaId) REFERENCES Empresas(Id)
            );
            CREATE TABLE IF NOT EXISTS OrganizacoesCompras (
                Id INTEGER PRIMARY KEY AUTOINCREMENT,
                EmpresaId INTEGER NOT NULL,
                Codigo TEXT UNIQUE,
                Nome TEXT NOT NULL,
                Moeda TEXT NOT NULL DEFAULT 'BRL',
                FOREIGN KEY(EmpresaId) REFERENCES Empresas(Id)
            );

            CREATE TABLE IF NOT EXISTS Clientes (
                Id INTEGER PRIMARY KEY AUTOINCREMENT,
                Nome TEXT NOT NULL,
                CpfCnpj TEXT,
                Email TEXT,
                Telefone TEXT,
                Endereco TEXT
            );
            CREATE TABLE IF NOT EXISTS Produtos (
                Id INTEGER PRIMARY KEY AUTOINCREMENT,
                Codigo TEXT,
                Nome TEXT NOT NULL,
                Preco REAL NOT NULL DEFAULT 0,
                Custo REAL NOT NULL DEFAULT 0,
                Estoque INTEGER NOT NULL DEFAULT 0
            );
            CREATE TABLE IF NOT EXISTS EstoqueDepositos (
                Id INTEGER PRIMARY KEY AUTOINCREMENT,
                ProdutoId INTEGER NOT NULL,
                DepositoId INTEGER NOT NULL,
                Quantidade INTEGER NOT NULL DEFAULT 0,
                FOREIGN KEY(ProdutoId) REFERENCES Produtos(Id),
                FOREIGN KEY(DepositoId) REFERENCES Depositos(Id),
                UNIQUE(ProdutoId, DepositoId)
            );
            CREATE TABLE IF NOT EXISTS Pedidos (
                Id INTEGER PRIMARY KEY AUTOINCREMENT,
                ClienteId INTEGER NOT NULL,
                EmpresaId INTEGER NOT NULL DEFAULT 0,
                CentroId INTEGER NOT NULL DEFAULT 0,
                DepositoId INTEGER NOT NULL DEFAULT 0,
                OrganizacaoVendasId INTEGER NOT NULL DEFAULT 0,
                Data TEXT NOT NULL,
                Status TEXT NOT NULL DEFAULT 'Aberto',
                FOREIGN KEY(ClienteId) REFERENCES Clientes(Id)
            );
            CREATE TABLE IF NOT EXISTS PedidoItens (
                Id INTEGER PRIMARY KEY AUTOINCREMENT,
                PedidoId INTEGER NOT NULL,
                ProdutoId INTEGER NOT NULL,
                PrecoUnitario REAL NOT NULL,
                Quantidade INTEGER NOT NULL,
                FOREIGN KEY(PedidoId) REFERENCES Pedidos(Id),
                FOREIGN KEY(ProdutoId) REFERENCES Produtos(Id)
            );
            """;
        cmd.ExecuteNonQuery();

        MigrarColunas();
        MigrarEstrutura();

        if (!UsuarioExiste("admin"))
            CriarUsuario(new Usuario
            {
                Nome = "Administrador",
                Login = "admin",
                Senha = "admin123",
                Admin = true
            });
    }

    // Adiciona colunas ausentes (útil quando o banco foi criado antes das mudanças de estrutura).
    private static void MigrarColunas()
    {
        string[] novasColunasPedidos =
        {
            "EmpresaId INTEGER NOT NULL DEFAULT 0",
            "CentroId INTEGER NOT NULL DEFAULT 0",
            "DepositoId INTEGER NOT NULL DEFAULT 0",
            "OrganizacaoVendasId INTEGER NOT NULL DEFAULT 0"
        };
        foreach (var def in novasColunasPedidos)
        {
            var nome = def.Split(' ')[0];
            if (!ColunaExiste("Pedidos", nome))
            {
                using var cmd = CriarComando();
                cmd.CommandText = $"ALTER TABLE Pedidos ADD COLUMN {nome} INTEGER NOT NULL DEFAULT 0";
                cmd.ExecuteNonQuery();
            }
        }
    }

    private static bool ColunaExiste(string tabela, string coluna)
    {
        using var cmd = CriarComando();
        cmd.CommandText = $"PRAGMA table_info({tabela})";
        using var r = cmd.ExecuteReader();
        while (r.Read())
        {
            if (r.GetString(1).Equals(coluna, StringComparison.OrdinalIgnoreCase))
                return true;
        }
        return false;
    }

    // Cria a estrutura organizacional padrão caso ainda não exista e
    // migra o estoque consolidado de Produtos para EstoqueDepositos.
    private static void MigrarEstrutura()
    {
        if (!TabelaVazia("Mandantes"))
            return;
        var mandante = CriarMandante(new Mandante
        {
            Codigo = "1000", Nome = "Grupo MeuERP",
            RazaoSocial = "Grupo MeuERP Ltda", Cnpj = "00.000.000/0001-00",
            Endereco = "Av. Central, 1000"
        });
        var empresa = CriarEmpresa(new Empresa
        {
            MandanteId = mandante.Id, Codigo = "1000",
            NomeFantasia = "MeuERP Matriz", RazaoSocial = "MeuERP Matriz Ltda",
            Cnpj = "00.000.000/0001-00", RegimeTributario = "Simples Nacional",
            Endereco = "Av. Central, 1000 - Sala 01"
        });
        var centro = CriarCentro(new Centro
        {
            EmpresaId = empresa.Id, Codigo = "1000",
            Nome = "Centro São Paulo", Tipo = "Sede",
            Endereco = "Av. Central, 1000 - Galpão 1"
        });
        var deposito = CriarDeposito(new Deposito
        {
            CentroId = centro.Id, Codigo = "1000",
            Nome = "Depósito Matriz", Tipo = "Operacional",
            Endereco = "Av. Central, 1000 - Almoxarifado"
        });
        _ = CriarOrganizacaoVendas(new OrganizacaoVendas
        {
            EmpresaId = empresa.Id, Codigo = "1000",
            Nome = "Vendas Brasil", Moeda = "BRL"
        });
        _ = CriarOrganizacaoCompras(new OrganizacaoCompras
        {
            EmpresaId = empresa.Id, Codigo = "1000",
            Nome = "Compras Brasil", Moeda = "BRL"
        });

        // Migra o estoque consolidado dos produtos existentes para o depósito padrão.
        foreach (var p in ObterProdutosBase())
        {
            if (p.Estoque > 0)
                AtualizarEstoque(p.Id, deposito.Id, p.Estoque);
        }
    }

    private static bool TabelaVazia(string tabela)
    {
        using var cmd = CriarComando();
        cmd.CommandText = $"SELECT COUNT(*) FROM {tabela}";
        return Convert.ToInt64(cmd.ExecuteScalar()) == 0;
    }

    public static SqliteConnection CriarConexao() => new($"Data Source={DbPath}");

    private static SqliteCommand CriarComando()
    {
        var conn = CriarConexao();
        conn.Open();
        return conn.CreateCommand();
    }

    public static string Criptografar(string texto) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(texto)));

    // ---------- Usuários ----------
    public static Usuario? Autenticar(string login, string senha)
    {
        var hash = Criptografar(senha);
        using var cmd = CriarComando();
        cmd.CommandText = "SELECT Id, Nome, Login, Admin FROM Usuarios WHERE Login = $l AND Senha = $s";
        cmd.Parameters.AddWithValue("$l", login);
        cmd.Parameters.AddWithValue("$s", hash);
        using var r = cmd.ExecuteReader();
        if (!r.Read()) return null;
        return new Usuario
        {
            Id = r.GetInt64(0),
            Nome = r.GetString(1),
            Login = r.GetString(2),
            Admin = r.GetInt64(3) == 1
        };
    }

    private static bool UsuarioExiste(string login)
    {
        using var cmd = CriarComando();
        cmd.CommandText = "SELECT COUNT(*) FROM Usuarios WHERE Login = $l";
        cmd.Parameters.AddWithValue("$l", login);
        return Convert.ToInt64(cmd.ExecuteScalar()) > 0;
    }

    public static void CriarUsuario(Usuario u)
    {
        using var cmd = CriarComando();
        cmd.CommandText = "INSERT INTO Usuarios (Nome, Login, Senha, Admin) VALUES ($n, $l, $s, $a)";
        cmd.Parameters.AddWithValue("$n", u.Nome);
        cmd.Parameters.AddWithValue("$l", u.Login);
        cmd.Parameters.AddWithValue("$s", Criptografar(u.Senha));
        cmd.Parameters.AddWithValue("$a", u.Admin ? 1 : 0);
        cmd.ExecuteNonQuery();
        u.Id = LerIdInsercao(cmd);
    }

    private static long LerIdInsercao(SqliteCommand cmd)
    {
        using var idCmd = cmd.Connection!.CreateCommand();
        idCmd.CommandText = "SELECT last_insert_rowid();";
        return Convert.ToInt64(idCmd.ExecuteScalar());
    }

    public static void AtualizarUsuario(Usuario u)
    {
        using var cmd = CriarComando();
        cmd.CommandText = "UPDATE Usuarios SET Nome = $n, Admin = $a WHERE Id = $id";
        cmd.Parameters.AddWithValue("$n", u.Nome);
        cmd.Parameters.AddWithValue("$a", u.Admin ? 1 : 0);
        cmd.Parameters.AddWithValue("$id", u.Id);
        cmd.ExecuteNonQuery();
    }

    public static void AtualizarSenha(long id, string novaSenha)
    {
        using var cmd = CriarComando();
        cmd.CommandText = "UPDATE Usuarios SET Senha = $s WHERE Id = $id";
        cmd.Parameters.AddWithValue("$s", Criptografar(novaSenha));
        cmd.Parameters.AddWithValue("$id", id);
        cmd.ExecuteNonQuery();
    }

    public static void ExcluirUsuario(long id)
    {
        using var cmd = CriarComando();
        cmd.CommandText = "DELETE FROM Usuarios WHERE Id = $id";
        cmd.Parameters.AddWithValue("$id", id);
        cmd.ExecuteNonQuery();
    }

    public static List<Usuario> ObterUsuarios()
    {
        var lista = new List<Usuario>();
        using var cmd = CriarComando();
        cmd.CommandText = "SELECT Id, Nome, Login, Admin FROM Usuarios ORDER BY Nome";
        using var r = cmd.ExecuteReader();
        while (r.Read())
            lista.Add(new Usuario
            {
                Id = r.GetInt64(0),
                Nome = r.GetString(1),
                Login = r.GetString(2),
                Admin = r.GetInt64(3) == 1
            });
        return lista;
    }

    // ---------- Clientes ----------
    public static void CriarCliente(Cliente c)
    {
        using var cmd = CriarComando();
        cmd.CommandText = "INSERT INTO Clientes (Nome, CpfCnpj, Email, Telefone, Endereco) VALUES ($n, $c, $e, $t, $e2)";
        AddParametrosCliente(cmd, c);
        cmd.ExecuteNonQuery();
        c.Id = LerIdInsercao(cmd);
    }

    public static void AtualizarCliente(Cliente c)
    {
        using var cmd = CriarComando();
        cmd.CommandText = "UPDATE Clientes SET Nome=$n, CpfCnpj=$c, Email=$e, Telefone=$t, Endereco=$e2 WHERE Id=$id";
        AddParametrosCliente(cmd, c);
        cmd.Parameters.AddWithValue("$id", c.Id);
        cmd.ExecuteNonQuery();
    }

    private static void AddParametrosCliente(SqliteCommand cmd, Cliente c)
    {
        cmd.Parameters.AddWithValue("$n", c.Nome);
        cmd.Parameters.AddWithValue("$c", c.CpfCnpj);
        cmd.Parameters.AddWithValue("$e", c.Email);
        cmd.Parameters.AddWithValue("$t", c.Telefone);
        cmd.Parameters.AddWithValue("$e2", c.Endereco);
    }

    public static void ExcluirCliente(long id)
    {
        using var cmd = CriarComando();
        cmd.CommandText = "DELETE FROM Clientes WHERE Id = $id";
        cmd.Parameters.AddWithValue("$id", id);
        cmd.ExecuteNonQuery();
    }

    public static List<Cliente> ObterClientes()
    {
        var lista = new List<Cliente>();
        using var cmd = CriarComando();
        cmd.CommandText = "SELECT Id, Nome, CpfCnpj, Email, Telefone, Endereco FROM Clientes ORDER BY Nome";
        using var r = cmd.ExecuteReader();
        while (r.Read())
            lista.Add(new Cliente
            {
                Id = r.GetInt64(0),
                Nome = r.GetString(1),
                CpfCnpj = r.IsDBNull(2) ? "" : r.GetString(2),
                Email = r.IsDBNull(3) ? "" : r.GetString(3),
                Telefone = r.IsDBNull(4) ? "" : r.GetString(4),
                Endereco = r.IsDBNull(5) ? "" : r.GetString(5)
            });
        return lista;
    }

    // ---------- Produtos ----------
    public static void CriarProduto(Produto p)
    {
        using var cmd = CriarComando();
        cmd.CommandText = "INSERT INTO Produtos (Codigo, Nome, Preco, Custo) VALUES ($c, $n, $p, $cu)";
        AddParametrosProduto(cmd, p);
        cmd.ExecuteNonQuery();
        p.Id = LerIdInsercao(cmd);
    }

    public static void AtualizarProduto(Produto p)
    {
        using var cmd = CriarComando();
        cmd.CommandText = "UPDATE Produtos SET Codigo=$c, Nome=$n, Preco=$p, Custo=$cu WHERE Id=$id";
        AddParametrosProduto(cmd, p);
        cmd.Parameters.AddWithValue("$id", p.Id);
        cmd.ExecuteNonQuery();
    }

    private static void AddParametrosProduto(SqliteCommand cmd, Produto p)
    {
        cmd.Parameters.AddWithValue("$c", p.Codigo);
        cmd.Parameters.AddWithValue("$n", p.Nome);
        cmd.Parameters.AddWithValue("$p", p.Preco);
        cmd.Parameters.AddWithValue("$cu", p.Custo);
    }

    public static void ExcluirProduto(long id)
    {
        using var cmd = CriarComando();
        cmd.CommandText = "DELETE FROM Produtos WHERE Id = $id";
        cmd.Parameters.AddWithValue("$id", id);
        cmd.ExecuteNonQuery();
    }

    public static Produto ObterProduto(long id)
    {
        using var cmd = CriarComando();
        cmd.CommandText = "SELECT Id, Codigo, Nome, Preco, Custo FROM Produtos WHERE Id = $id";
        cmd.Parameters.AddWithValue("$id", id);
        using var r = cmd.ExecuteReader();
        if (!r.Read()) return null!;
        return new Produto
        {
            Id = r.GetInt64(0),
            Codigo = r.IsDBNull(1) ? "" : r.GetString(1),
            Nome = r.GetString(2),
            Preco = Convert.ToDecimal(r.GetDouble(3)),
            Custo = Convert.ToDecimal(r.GetDouble(4))
        };
    }

    // Consulta base de produtos (sem estoque consolidado).
    private static List<Produto> ObterProdutosBase()
    {
        var lista = new List<Produto>();
        using var cmd = CriarComando();
        cmd.CommandText = "SELECT Id, Codigo, Nome, Preco, Custo FROM Produtos ORDER BY Nome";
        using var r = cmd.ExecuteReader();
        while (r.Read())
            lista.Add(new Produto
            {
                Id = r.GetInt64(0),
                Codigo = r.IsDBNull(1) ? "" : r.GetString(1),
                Nome = r.GetString(2),
                Preco = r.GetDouble(3) == 0 ? 0 : Convert.ToDecimal(r.GetDouble(3)),
                Custo = Convert.ToDecimal(r.GetDouble(4)),
                Estoque = 0
            });
        return lista;
    }

    public static List<Produto> ObterProdutos()
    {
        var lista = new List<Produto>();
        using var cmd = CriarComando();
        cmd.CommandText = """
            SELECT Id, Codigo, Nome, Preco, Custo, COALESCE(e.QuantidadeTotal, 0)
            FROM Produtos p
            LEFT JOIN (
                SELECT ProdutoId, SUM(Quantidade) AS QuantidadeTotal
                FROM EstoqueDepositos GROUP BY ProdutoId
            ) e ON e.ProdutoId = p.Id
            ORDER BY p.Nome
            """;
        using var r = cmd.ExecuteReader();
        while (r.Read())
            lista.Add(new Produto
            {
                Id = r.GetInt64(0),
                Codigo = r.IsDBNull(1) ? "" : r.GetString(1),
                Nome = r.GetString(2),
                Preco = r.GetDouble(3) == 0 ? 0 : Convert.ToDecimal(r.GetDouble(3)),
                Custo = Convert.ToDecimal(r.GetDouble(4)),
                Estoque = r.GetInt32(5)
            });
        return lista;
    }

    // ---------- Estoque por Depósito ----------
    public static List<EstoqueDeposito> ObterEstoque(long produtoId)
    {
        var lista = new List<EstoqueDeposito>();
        using var cmd = CriarComando();
        cmd.CommandText = """
            SELECT e.Id, e.ProdutoId, p.Nome, e.DepositoId, d.Nome, d.CentroId, c.EmpresaId, e.Quantidade
            FROM EstoqueDepositos e
            INNER JOIN Produtos p ON p.Id = e.ProdutoId
            INNER JOIN Depositos d ON d.Id = e.DepositoId
            INNER JOIN Centros c ON c.Id = d.CentroId
            WHERE e.ProdutoId = $id
            ORDER BY d.Nome
            """;
        cmd.Parameters.AddWithValue("$id", produtoId);
        using var r = cmd.ExecuteReader();
        while (r.Read())
            lista.Add(new EstoqueDeposito
            {
                Id = r.GetInt64(0),
                ProdutoId = r.GetInt64(1),
                ProdutoNome = r.GetString(2),
                DepositoId = r.GetInt64(3),
                DepositoNome = r.GetString(4),
                CentroId = r.GetInt64(5),
                EmpresaId = r.GetInt64(6),
                Quantidade = r.GetInt32(7)
            });
        return lista;
    }

    public static List<EstoqueDeposito> ObterEstoqueGeral()
    {
        var lista = new List<EstoqueDeposito>();
        using var cmd = CriarComando();
        cmd.CommandText = """
            SELECT e.Id, e.ProdutoId, p.Nome, e.DepositoId, d.Nome, d.CentroId, c.EmpresaId, e.Quantidade
            FROM EstoqueDepositos e
            INNER JOIN Produtos p ON p.Id = e.ProdutoId
            INNER JOIN Depositos d ON d.Id = e.DepositoId
            INNER JOIN Centros c ON c.Id = d.CentroId
            WHERE e.Quantidade <> 0
            ORDER BY p.Nome, d.Nome
            """;
        using var r = cmd.ExecuteReader();
        while (r.Read())
            lista.Add(new EstoqueDeposito
            {
                Id = r.GetInt64(0),
                ProdutoId = r.GetInt64(1),
                ProdutoNome = r.GetString(2),
                DepositoId = r.GetInt64(3),
                DepositoNome = r.GetString(4),
                CentroId = r.GetInt64(5),
                EmpresaId = r.GetInt64(6),
                Quantidade = r.GetInt32(7)
            });
        return lista;
    }

    // Como obter saldo disponível de um produto em um depósito.
    public static int ObterSaldo(long produtoId, long depositoId)
    {
        using var cmd = CriarComando();
        cmd.CommandText = "SELECT Quantidade FROM EstoqueDepositos WHERE ProdutoId = $p AND DepositoId = $d";
        cmd.Parameters.AddWithValue("$p", produtoId);
        cmd.Parameters.AddWithValue("$d", depositoId);
        var valor = cmd.ExecuteScalar();
        return valor == null ? 0 : Convert.ToInt32(valor);
    }

    // Movimenta estoque de um produto em um depósito específico (positivo/negativo).
    public static void AtualizarEstoque(long produtoId, long depositoId, int quantidade)
    {
        using var cmd = CriarComando();
        cmd.CommandText = """
            INSERT INTO EstoqueDepositos (ProdutoId, DepositoId, Quantidade)
            VALUES ($p, $d, $q)
            ON CONFLICT(ProdutoId, DepositoId)
            DO UPDATE SET Quantidade = Quantidade + excluded.Quantidade
            """;
        cmd.Parameters.AddWithValue("$p", produtoId);
        cmd.Parameters.AddWithValue("$d", depositoId);
        cmd.Parameters.AddWithValue("$q", quantidade);
        cmd.ExecuteNonQuery();
    }

    public static void DefinirEstoque(long produtoId, long depositoId, int quantidade)
    {
        using var cmd = CriarComando();
        cmd.CommandText = """
            INSERT INTO EstoqueDepositos (ProdutoId, DepositoId, Quantidade)
            VALUES ($p, $d, $q)
            ON CONFLICT(ProdutoId, DepositoId)
            DO UPDATE SET Quantidade = excluded.Quantidade
            """;
        cmd.Parameters.AddWithValue("$p", produtoId);
        cmd.Parameters.AddWithValue("$d", depositoId);
        cmd.Parameters.AddWithValue("$q", quantidade);
        cmd.ExecuteNonQuery();
    }

    // ---------- Mandantes ----------
    public static Mandante CriarMandante(Mandante m)
    {
        using var cmd = CriarComando();
        cmd.CommandText = "INSERT INTO Mandantes (Codigo, Nome, RazaoSocial, Cnpj, Endereco) VALUES ($c, $n, $r, $cn, $e)";
        AddParametrosMandante(cmd, m);
        cmd.ExecuteNonQuery();
        m.Id = LerIdInsercao(cmd);
        return m;
    }

    public static void AtualizarMandante(Mandante m)
    {
        using var cmd = CriarComando();
        cmd.CommandText = "UPDATE Mandantes SET Codigo=$c, Nome=$n, RazaoSocial=$r, Cnpj=$cn, Endereco=$e WHERE Id=$id";
        AddParametrosMandante(cmd, m);
        cmd.Parameters.AddWithValue("$id", m.Id);
        cmd.ExecuteNonQuery();
    }

    private static void AddParametrosMandante(SqliteCommand cmd, Mandante m)
    {
        cmd.Parameters.AddWithValue("$c", m.Codigo);
        cmd.Parameters.AddWithValue("$n", m.Nome);
        cmd.Parameters.AddWithValue("$r", m.RazaoSocial);
        cmd.Parameters.AddWithValue("$cn", m.Cnpj);
        cmd.Parameters.AddWithValue("$e", m.Endereco);
    }

    public static void ExcluirMandante(long id)
    {
        using var cmd = CriarComando();
        cmd.CommandText = "DELETE FROM Mandantes WHERE Id = $id";
        cmd.Parameters.AddWithValue("$id", id);
        cmd.ExecuteNonQuery();
    }

    public static List<Mandante> ObterMandantes()
    {
        var lista = new List<Mandante>();
        using var cmd = CriarComando();
        cmd.CommandText = "SELECT Id, Codigo, Nome, RazaoSocial, Cnpj, Endereco FROM Mandantes ORDER BY Codigo";
        using var r = cmd.ExecuteReader();
        while (r.Read())
            lista.Add(new Mandante
            {
                Id = r.GetInt64(0),
                Codigo = r.IsDBNull(1) ? "" : r.GetString(1),
                Nome = r.GetString(2),
                RazaoSocial = r.IsDBNull(3) ? "" : r.GetString(3),
                Cnpj = r.IsDBNull(4) ? "" : r.GetString(4),
                Endereco = r.IsDBNull(5) ? "" : r.GetString(5)
            });
        return lista;
    }

    // ---------- Empresas ----------
    public static Empresa CriarEmpresa(Empresa e)
    {
        using var cmd = CriarComando();
        cmd.CommandText = """
            INSERT INTO Empresas (MandanteId, Codigo, NomeFantasia, RazaoSocial, Cnpj, RegimeTributario, Endereco)
            VALUES ($m, $c, $n, $r, $cn, $rt, $e)
            """;
        AddParametrosEmpresa(cmd, e);
        cmd.ExecuteNonQuery();
        e.Id = LerIdInsercao(cmd);
        return e;
    }

    public static void AtualizarEmpresa(Empresa e)
    {
        using var cmd = CriarComando();
        cmd.CommandText = """
            UPDATE Empresas SET MandanteId=$m, Codigo=$c, NomeFantasia=$n, RazaoSocial=$r,
                Cnpj=$cn, RegimeTributario=$rt, Endereco=$e2 WHERE Id=$id
            """;
        AddParametrosEmpresa(cmd, e);
        cmd.Parameters.AddWithValue("$id", e.Id);
        cmd.ExecuteNonQuery();
    }

    private static void AddParametrosEmpresa(SqliteCommand cmd, Empresa e)
    {
        cmd.Parameters.AddWithValue("$m", e.MandanteId);
        cmd.Parameters.AddWithValue("$c", e.Codigo);
        cmd.Parameters.AddWithValue("$n", e.NomeFantasia);
        cmd.Parameters.AddWithValue("$r", e.RazaoSocial);
        cmd.Parameters.AddWithValue("$cn", e.Cnpj);
        cmd.Parameters.AddWithValue("$rt", e.RegimeTributario);
        cmd.Parameters.AddWithValue("$e", e.Endereco);
    }

    public static void ExcluirEmpresa(long id)
    {
        using var cmd = CriarComando();
        cmd.CommandText = "DELETE FROM Empresas WHERE Id = $id";
        cmd.Parameters.AddWithValue("$id", id);
        cmd.ExecuteNonQuery();
    }

    public static List<Empresa> ObterEmpresas()
    {
        var lista = new List<Empresa>();
        using var cmd = CriarComando();
        cmd.CommandText = """
            SELECT e.Id, e.MandanteId, m.Nome, e.Codigo, e.NomeFantasia, e.RazaoSocial,
                   e.Cnpj, e.RegimeTributario, e.Endereco
            FROM Empresas e
            LEFT JOIN Mandantes m ON m.Id = e.MandanteId
            ORDER BY e.Codigo
            """;
        using var r = cmd.ExecuteReader();
        while (r.Read())
            lista.Add(new Empresa
            {
                Id = r.GetInt64(0),
                MandanteId = r.GetInt64(1),
                MandanteNome = r.IsDBNull(2) ? "" : r.GetString(2),
                Codigo = r.IsDBNull(3) ? "" : r.GetString(3),
                NomeFantasia = r.GetString(4),
                RazaoSocial = r.IsDBNull(5) ? "" : r.GetString(5),
                Cnpj = r.IsDBNull(6) ? "" : r.GetString(6),
                RegimeTributario = r.IsDBNull(7) ? "" : r.GetString(7),
                Endereco = r.IsDBNull(8) ? "" : r.GetString(8)
            });
        return lista;
    }

    // ---------- Centros ----------
    public static Centro CriarCentro(Centro c)
    {
        using var cmd = CriarComando();
        cmd.CommandText = "INSERT INTO Centros (EmpresaId, Codigo, Nome, Tipo, Endereco) VALUES ($e, $c, $n, $t, $e2)";
        AddParametrosCentro(cmd, c);
        cmd.ExecuteNonQuery();
        c.Id = LerIdInsercao(cmd);
        return c;
    }

    public static void AtualizarCentro(Centro c)
    {
        using var cmd = CriarComando();
        cmd.CommandText = "UPDATE Centros SET EmpresaId=$e, Codigo=$c, Nome=$n, Tipo=$t, Endereco=$e2 WHERE Id=$id";
        AddParametrosCentro(cmd, c);
        cmd.Parameters.AddWithValue("$id", c.Id);
        cmd.ExecuteNonQuery();
    }

    private static void AddParametrosCentro(SqliteCommand cmd, Centro c)
    {
        cmd.Parameters.AddWithValue("$e", c.EmpresaId);
        cmd.Parameters.AddWithValue("$c", c.Codigo);
        cmd.Parameters.AddWithValue("$n", c.Nome);
        cmd.Parameters.AddWithValue("$t", c.Tipo);
        cmd.Parameters.AddWithValue("$e2", c.Endereco);
    }

    public static void ExcluirCentro(long id)
    {
        using var cmd = CriarComando();
        cmd.CommandText = "DELETE FROM Centros WHERE Id = $id";
        cmd.Parameters.AddWithValue("$id", id);
        cmd.ExecuteNonQuery();
    }

    public static List<Centro> ObterCentros()
    {
        var lista = new List<Centro>();
        using var cmd = CriarComando();
        cmd.CommandText = """
            SELECT c.Id, c.EmpresaId, e.NomeFantasia, c.Codigo, c.Nome, c.Tipo, c.Endereco
            FROM Centros c
            LEFT JOIN Empresas e ON e.Id = c.EmpresaId
            ORDER BY c.Codigo
            """;
        using var r = cmd.ExecuteReader();
        while (r.Read())
            lista.Add(new Centro
            {
                Id = r.GetInt64(0),
                EmpresaId = r.GetInt64(1),
                EmpresaNome = r.IsDBNull(2) ? "" : r.GetString(2),
                Codigo = r.IsDBNull(3) ? "" : r.GetString(3),
                Nome = r.GetString(4),
                Tipo = r.IsDBNull(5) ? "" : r.GetString(5),
                Endereco = r.IsDBNull(6) ? "" : r.GetString(6)
            });
        return lista;
    }

    // ---------- Depósitos ----------
    public static Deposito CriarDeposito(Deposito d)
    {
        using var cmd = CriarComando();
        cmd.CommandText = "INSERT INTO Depositos (CentroId, Codigo, Nome, Tipo, Endereco) VALUES ($c, $cd, $n, $t, $e)";
        AddParametrosDeposito(cmd, d);
        cmd.ExecuteNonQuery();
        d.Id = LerIdInsercao(cmd);
        return d;
    }

    public static void AtualizarDeposito(Deposito d)
    {
        using var cmd = CriarComando();
        cmd.CommandText = "UPDATE Depositos SET CentroId=$c, Codigo=$cd, Nome=$n, Tipo=$t, Endereco=$e WHERE Id=$id";
        AddParametrosDeposito(cmd, d);
        cmd.Parameters.AddWithValue("$id", d.Id);
        cmd.ExecuteNonQuery();
    }

    private static void AddParametrosDeposito(SqliteCommand cmd, Deposito d)
    {
        cmd.Parameters.AddWithValue("$c", d.CentroId);
        cmd.Parameters.AddWithValue("$cd", d.Codigo);
        cmd.Parameters.AddWithValue("$n", d.Nome);
        cmd.Parameters.AddWithValue("$t", d.Tipo);
        cmd.Parameters.AddWithValue("$e", d.Endereco);
    }

    public static void ExcluirDeposito(long id)
    {
        using var cmd = CriarComando();
        cmd.CommandText = "DELETE FROM Depositos WHERE Id = $id";
        cmd.Parameters.AddWithValue("$id", id);
        cmd.ExecuteNonQuery();
    }

    public static List<Deposito> ObterDepositos()
    {
        var lista = new List<Deposito>();
        using var cmd = CriarComando();
        cmd.CommandText = """
            SELECT d.Id, d.CentroId, c.Nome, d.Codigo, d.Nome, d.Tipo, d.Endereco
            FROM Depositos d
            LEFT JOIN Centros c ON c.Id = d.CentroId
            ORDER BY d.Codigo
            """;
        using var r = cmd.ExecuteReader();
        while (r.Read())
            lista.Add(new Deposito
            {
                Id = r.GetInt64(0),
                CentroId = r.GetInt64(1),
                CentroNome = r.IsDBNull(2) ? "" : r.GetString(2),
                Codigo = r.IsDBNull(3) ? "" : r.GetString(3),
                Nome = r.GetString(4),
                Tipo = r.IsDBNull(5) ? "" : r.GetString(5),
                Endereco = r.IsDBNull(6) ? "" : r.GetString(6)
            });
        return lista;
    }

    // ---------- Organizações de Vendas ----------
    public static OrganizacaoVendas CriarOrganizacaoVendas(OrganizacaoVendas v)
    {
        using var cmd = CriarComando();
        cmd.CommandText = "INSERT INTO OrganizacoesVendas (EmpresaId, Codigo, Nome, Moeda) VALUES ($e, $c, $n, $m)";
        cmd.Parameters.AddWithValue("$e", v.EmpresaId);
        cmd.Parameters.AddWithValue("$c", v.Codigo);
        cmd.Parameters.AddWithValue("$n", v.Nome);
        cmd.Parameters.AddWithValue("$m", v.Moeda);
        cmd.ExecuteNonQuery();
        v.Id = LerIdInsercao(cmd);
        return v;
    }

    public static void AtualizarOrganizacaoVendas(OrganizacaoVendas v)
    {
        using var cmd = CriarComando();
        cmd.CommandText = "UPDATE OrganizacoesVendas SET EmpresaId=$e, Codigo=$c, Nome=$n, Moeda=$m WHERE Id=$id";
        cmd.Parameters.AddWithValue("$e", v.EmpresaId);
        cmd.Parameters.AddWithValue("$c", v.Codigo);
        cmd.Parameters.AddWithValue("$n", v.Nome);
        cmd.Parameters.AddWithValue("$m", v.Moeda);
        cmd.Parameters.AddWithValue("$id", v.Id);
        cmd.ExecuteNonQuery();
    }

    public static void ExcluirOrganizacaoVendas(long id)
    {
        using var cmd = CriarComando();
        cmd.CommandText = "DELETE FROM OrganizacoesVendas WHERE Id = $id";
        cmd.Parameters.AddWithValue("$id", id);
        cmd.ExecuteNonQuery();
    }

    public static List<OrganizacaoVendas> ObterOrganizacoesVendas()
    {
        var lista = new List<OrganizacaoVendas>();
        using var cmd = CriarComando();
        cmd.CommandText = """
            SELECT v.Id, v.EmpresaId, e.NomeFantasia, v.Codigo, v.Nome, v.Moeda
            FROM OrganizacoesVendas v
            LEFT JOIN Empresas e ON e.Id = v.EmpresaId
            ORDER BY v.Codigo
            """;
        using var r = cmd.ExecuteReader();
        while (r.Read())
            lista.Add(new OrganizacaoVendas
            {
                Id = r.GetInt64(0),
                EmpresaId = r.GetInt64(1),
                EmpresaNome = r.IsDBNull(2) ? "" : r.GetString(2),
                Codigo = r.IsDBNull(3) ? "" : r.GetString(3),
                Nome = r.GetString(4),
                Moeda = r.IsDBNull(5) ? "BRL" : r.GetString(5)
            });
        return lista;
    }

    // ---------- Organizações de Compras ----------
    public static OrganizacaoCompras CriarOrganizacaoCompras(OrganizacaoCompras c)
    {
        using var cmd = CriarComando();
        cmd.CommandText = "INSERT INTO OrganizacoesCompras (EmpresaId, Codigo, Nome, Moeda) VALUES ($e, $cd, $n, $m)";
        cmd.Parameters.AddWithValue("$e", c.EmpresaId);
        cmd.Parameters.AddWithValue("$cd", c.Codigo);
        cmd.Parameters.AddWithValue("$n", c.Nome);
        cmd.Parameters.AddWithValue("$m", c.Moeda);
        cmd.ExecuteNonQuery();
        c.Id = LerIdInsercao(cmd);
        return c;
    }

    public static void AtualizarOrganizacaoCompras(OrganizacaoCompras c)
    {
        using var cmd = CriarComando();
        cmd.CommandText = "UPDATE OrganizacoesCompras SET EmpresaId=$e, Codigo=$cd, Nome=$n, Moeda=$m WHERE Id=$id";
        cmd.Parameters.AddWithValue("$e", c.EmpresaId);
        cmd.Parameters.AddWithValue("$cd", c.Codigo);
        cmd.Parameters.AddWithValue("$n", c.Nome);
        cmd.Parameters.AddWithValue("$m", c.Moeda);
        cmd.Parameters.AddWithValue("$id", c.Id);
        cmd.ExecuteNonQuery();
    }

    public static void ExcluirOrganizacaoCompras(long id)
    {
        using var cmd = CriarComando();
        cmd.CommandText = "DELETE FROM OrganizacoesCompras WHERE Id = $id";
        cmd.Parameters.AddWithValue("$id", id);
        cmd.ExecuteNonQuery();
    }

    public static List<OrganizacaoCompras> ObterOrganizacoesCompras()
    {
        var lista = new List<OrganizacaoCompras>();
        using var cmd = CriarComando();
        cmd.CommandText = """
            SELECT c.Id, c.EmpresaId, e.NomeFantasia, c.Codigo, c.Nome, c.Moeda
            FROM OrganizacoesCompras c
            LEFT JOIN Empresas e ON e.Id = c.EmpresaId
            ORDER BY c.Codigo
            """;
        using var r = cmd.ExecuteReader();
        while (r.Read())
            lista.Add(new OrganizacaoCompras
            {
                Id = r.GetInt64(0),
                EmpresaId = r.GetInt64(1),
                EmpresaNome = r.IsDBNull(2) ? "" : r.GetString(2),
                Codigo = r.IsDBNull(3) ? "" : r.GetString(3),
                Nome = r.GetString(4),
                Moeda = r.IsDBNull(5) ? "BRL" : r.GetString(5)
            });
        return lista;
    }

    // ---------- Pedidos ----------
    public static Pedido CriarPedido(Pedido p)
    {
        using var cmd = CriarComando();
        cmd.CommandText = """
            INSERT INTO Pedidos (ClienteId, EmpresaId, CentroId, DepositoId, OrganizacaoVendasId, Data, Status)
            VALUES ($c, $e, $ce, $d, $v, $dt, $s)
            """;
        cmd.Parameters.AddWithValue("$c", p.ClienteId);
        cmd.Parameters.AddWithValue("$e", p.EmpresaId);
        cmd.Parameters.AddWithValue("$ce", p.CentroId);
        cmd.Parameters.AddWithValue("$d", p.DepositoId);
        cmd.Parameters.AddWithValue("$v", p.OrganizacaoVendasId);
        cmd.Parameters.AddWithValue("$dt", p.Data.ToString("yyyy-MM-dd HH:mm:ss"));
        cmd.Parameters.AddWithValue("$s", p.Status);
        cmd.ExecuteNonQuery();
        using (var idCmd = cmd.Connection!.CreateCommand())
        {
            idCmd.CommandText = "SELECT last_insert_rowid();";
            p.Id = Convert.ToInt64(idCmd.ExecuteScalar());
        }

        foreach (var item in p.Itens)
        {
            using var icmd = CriarComando();
            icmd.CommandText = "INSERT INTO PedidoItens (PedidoId, ProdutoId, PrecoUnitario, Quantidade) VALUES ($p, $pr, $v, $q)";
            icmd.Parameters.AddWithValue("$p", p.Id);
            icmd.Parameters.AddWithValue("$pr", item.ProdutoId);
            icmd.Parameters.AddWithValue("$v", item.PrecoUnitario);
            icmd.Parameters.AddWithValue("$q", item.Quantidade);
            icmd.ExecuteNonQuery();
        }
        return p;
    }

    public static void AtualizarStatus(long pedidoId, string status)
    {
        using var cmd = CriarComando();
        cmd.CommandText = "UPDATE Pedidos SET Status = $s WHERE Id = $id";
        cmd.Parameters.AddWithValue("$s", status);
        cmd.Parameters.AddWithValue("$id", pedidoId);
        cmd.ExecuteNonQuery();
    }

    public static void ExcluirPedido(long id)
    {
        using var cmd = CriarComando();
        cmd.CommandText = "DELETE FROM PedidoItens WHERE PedidoId = $id";
        cmd.Parameters.AddWithValue("$id", id);
        cmd.ExecuteNonQuery();
        using var cmd2 = CriarComando();
        cmd2.CommandText = "DELETE FROM Pedidos WHERE Id = $id";
        cmd2.Parameters.AddWithValue("$id", id);
        cmd2.ExecuteNonQuery();
    }

    public static List<Pedido> ObterPedidos()
    {
        var lista = new List<Pedido>();
        using var cmd = CriarComando();
        cmd.CommandText = """
            SELECT p.Id, p.ClienteId, c.Nome, p.Data, p.Status,
                   COALESCE(SUM(i.PrecoUnitario * i.Quantidade), 0),
                   p.EmpresaId, p.CentroId, p.DepositoId, p.OrganizacaoVendasId,
                   COALESCE(e.NomeFantasia,''), COALESCE(ce.Nome,''),
                   COALESCE(d.Nome,''), COALESCE(v.Nome,'')
            FROM Pedidos p
            LEFT JOIN Clientes c ON c.Id = p.ClienteId
            LEFT JOIN PedidoItens i ON i.PedidoId = p.Id
            LEFT JOIN Empresas e ON e.Id = p.EmpresaId
            LEFT JOIN Centros ce ON ce.Id = p.CentroId
            LEFT JOIN Depositos d ON d.Id = p.DepositoId
            LEFT JOIN OrganizacoesVendas v ON v.Id = p.OrganizacaoVendasId
            GROUP BY p.Id
            ORDER BY p.Id DESC
            """;
        using var r = cmd.ExecuteReader();
        while (r.Read())
            lista.Add(new Pedido
            {
                Id = r.GetInt64(0),
                ClienteId = r.GetInt64(1),
                ClienteNome = r.IsDBNull(2) ? "" : r.GetString(2),
                Data = DateTime.Parse(r.GetString(3)),
                Status = r.GetString(4),
                Itens = new List<PedidoItem>(),
                EmpresaId = r.GetInt64(6),
                CentroId = r.GetInt64(7),
                DepositoId = r.GetInt64(8),
                OrganizacaoVendasId = r.GetInt64(9),
                EmpresaNome = r.IsDBNull(10) ? "" : r.GetString(10),
                CentroNome = r.IsDBNull(11) ? "" : r.GetString(11),
                DepositoNome = r.IsDBNull(12) ? "" : r.GetString(12),
                OrganizacaoVendasNome = r.IsDBNull(13) ? "" : r.GetString(13)
            });
        return lista;
    }

    public static List<PedidoItem> ObterItens(long pedidoId)
    {
        var lista = new List<PedidoItem>();
        using var cmd = CriarComando();
        cmd.CommandText = """
            SELECT i.Id, i.PedidoId, i.ProdutoId, pr.Nome, i.PrecoUnitario, i.Quantidade
            FROM PedidoItens i
            LEFT JOIN Produtos pr ON pr.Id = i.ProdutoId
            WHERE i.PedidoId = $id
            """;
        cmd.Parameters.AddWithValue("$id", pedidoId);
        using var r = cmd.ExecuteReader();
        while (r.Read())
            lista.Add(new PedidoItem
            {
                Id = r.GetInt64(0),
                PedidoId = r.GetInt64(1),
                ProdutoId = r.GetInt64(2),
                ProdutoNome = r.IsDBNull(3) ? "" : r.GetString(3),
                PrecoUnitario = Convert.ToDecimal(r.GetDouble(4)),
                Quantidade = r.GetInt32(5)
            });
        return lista;
    }
}