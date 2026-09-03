# ERP Plataforma

Sistema de gestão (ERP) com **frontend estático** em `wwwroot/` servido pelo **GitHub Pages** e **API .NET** hospedada externamente.

## Arquitetura

```
┌─────────────────────────┐      fetch/rest       ┌──────────────────────┐
│  GitHub Pages            │  ──────────────────► │  API externa (.NET)  │
│  frontend estático       │     Auth: Bearer     │  controllers, banco  │
│  (wwwroot/)             │  ◄──────────────────  │  JWT                 │
└─────────────────────────┘                       └──────────────────────┘
```

- **Frontend:** arquivos estáticos em `wwwroot/` (HTML/CSS/JS). O `index.html` é um SPA que consome a API via `fetch`.
- **API:** backend ASP.NET Core existente, exposto em um servidor externo (Azure, Railway, Render, VPS, etc.) com CORS liberado.
- **Banco de dados:** gerenciado pela API (SQLite/outro).

## Configurando a URL da API

O frontend lê a URL da API de `wwwroot/config.js`:

```js
window.MEUERP_API = '';
```

- **Local (dev):** deixe vazio `''` (a API local responde na mesma origem).
- **Produção (Pages):** informe o endereço público da API, ex.:

```js
window.MEUERP_API = 'https://meuerp-api.example.com';
```

> Importante: a API precisa ter CORS habilitado para aceitar a origem do GitHub Pages (`https://usuario.github.io`). Já está liberado com `AllowAnyOrigin` no `Program.cs`.

## Deploy no GitHub Pages (frontend)

1. **Aponte a URL da API** em `wwwroot/config.js` para o endereço do seu servidor.

2. No GitHub do repositório, vá em **Settings → Pages**, em **Source** escolha **GitHub Actions**.

3. Faça commit e push (o workflow `.github/workflows/pages.yml` publica a pasta `wwwroot/`).

4. Acesse `https://usuario.github.io/erp-plataforma/`.

> O workflow dispara em push para `main`/`master` ou manualmente via **Actions → Deploy GitHub Pages → Run workflow**.

## Deploy da API (.NET) externa

Publique o backend em qualquer PaaS/VPS que rode .NET:

```bash
dotnet publish -c Release -o ./publish
```

Após subir o backend, o frontend do Pages usa o token JWT retornado no login para autenticar as chamadas aos endpoints REST.

## Rodando local

```bash
dotnet run
```

O navegador abre em `http://localhost:5003/`. Com `config.js` vazio, o frontend consome a API local na mesma origem.