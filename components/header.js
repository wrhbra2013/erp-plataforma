document.write('\
<div class="app-layout">\
  <div id="sidebarOverlay" class="sidebar-overlay"></div>\
  <aside id="sidebar" class="sidebar">\
    <div class="sidebar-logo">\
      <h2><span>ERP</span> Fiscal</h2>\
      <div style="font-size:0.7rem;color:rgba(255,255,255,0.4);margin-top:2px;">Plataforma de Gestão</div>\
    </div>\
    <nav class="sidebar-nav">\
      <div class="nav-section">Principal</div>\
      <a href="' + ROOT + '/index.html"><i class="bi bi-grid"></i> Dashboard</a>\
      <div class="nav-section">Gestão</div>\
      <a href="' + ROOT + '/pages/clientes.html"><i class="bi bi-people"></i> Clientes</a>\
      <a href="' + ROOT + '/pages/fornecedores.html"><i class="bi bi-truck"></i> Fornecedores</a>\
      <a href="' + ROOT + '/pages/produtos.html"><i class="bi bi-box"></i> Produtos</a>\
      <div class="nav-section">Fiscal</div>\
      <a href="' + ROOT + '/pages/calculadora-tributos.html"><i class="bi bi-calculator"></i> Calculadora Tributária</a>\
      <a href="' + ROOT + '/pages/emissao-nfe.html"><i class="bi bi-file-earmark-text"></i> Emissão NF-e</a>\
      <div class="nav-section">Operacional</div>\
      <a href="' + ROOT + '/pages/vendas.html"><i class="bi bi-cart"></i> Vendas</a>\
      <a href="' + ROOT + '/pages/relatorios.html"><i class="bi bi-bar-chart"></i> Relatórios</a>\
      <div class="nav-section">Sistema</div>\
      <a href="' + ROOT + '/pages/configuracoes.html"><i class="bi bi-gear"></i> Configurações</a>\
      <a href="#" onclick="API.logout();return false;"><i class="bi bi-box-arrow-right"></i> Sair</a>\
    </nav>\
  </aside>\
  <div class="main-area">\
    <header class="topbar">\
      <div class="topbar-left">\
        <button id="menuToggle" class="menu-toggle" aria-label="Menu"><i class="bi bi-list"></i></button>\
        <span id="pageTitle" style="font-weight:600;font-size:1.05rem;">Dashboard</span>\
      </div>\
      <div class="topbar-right">\
        <span style="font-size:0.85rem;color:var(--text-muted);" id="userDisplay"></span>\
        <span class="badge badge-success" style="font-size:0.7rem;" id="apiStatus">Conectado</span>\
      </div>\
    </header>\
    <main class="page-content">');
