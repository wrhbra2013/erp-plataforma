document.addEventListener('DOMContentLoaded', function() {
  // Mobile sidebar toggle
  var menuToggle = document.getElementById('menuToggle');
  var sidebar = document.getElementById('sidebar');
  var sidebarOverlay = document.getElementById('sidebarOverlay');

  if (menuToggle && sidebar) {
    menuToggle.addEventListener('click', function() {
      sidebar.classList.toggle('open');
      if (sidebarOverlay) sidebarOverlay.classList.toggle('active');
    });
  }

  if (sidebarOverlay) {
    sidebarOverlay.addEventListener('click', function() {
      sidebar.classList.remove('open');
      sidebarOverlay.classList.remove('active');
    });
  }

  // Highlight active nav link
  var currentPath = window.location.pathname;
  var navLinks = document.querySelectorAll('.sidebar-nav a');
  navLinks.forEach(function(link) {
    var href = link.getAttribute('href');
    if (href && currentPath.indexOf(href) !== -1) {
      link.classList.add('active');
    }
  });

  // Format currency inputs
  document.querySelectorAll('.input-currency').forEach(function(input) {
    input.addEventListener('input', function(e) {
      var v = this.value.replace(/\D/g, '');
      v = (parseInt(v) / 100).toFixed(2);
      if (!isNaN(v)) this.value = 'R$ ' + v.replace('.', ',');
    });
  });

  // Format CNPJ/CPF
  document.querySelectorAll('.input-cnpj').forEach(function(input) {
    input.addEventListener('input', function(e) {
      var v = this.value.replace(/\D/g, '').slice(0, 14);
      if (v.length <= 11) {
        this.value = v.replace(/(\d{3})(\d{3})(\d{3})(\d{2})/, '$1.$2.$3-$4');
      } else {
        this.value = v.replace(/(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})/, '$1.$2.$3/$4-$5');
      }
    });
  });

  // Format CEP
  document.querySelectorAll('.input-cep').forEach(function(input) {
    input.addEventListener('input', function(e) {
      var v = this.value.replace(/\D/g, '').slice(0, 8);
      this.value = v.replace(/(\d{5})(\d{3})/, '$1-$2');
    });
  });

  // Format phone
  document.querySelectorAll('.input-phone').forEach(function(input) {
    input.addEventListener('input', function(e) {
      var v = this.value.replace(/\D/g, '').slice(0, 11);
      if (v.length <= 10) {
        this.value = v.replace(/(\d{2})(\d{4})(\d{4})/, '($1) $2-$3');
      } else {
        this.value = v.replace(/(\d{2})(\d{5})(\d{4})/, '($1) $2-$3');
      }
    });
  });
});

function formatCurrency(v) {
  return 'R$ ' + Number(v).toFixed(2).replace('.', ',');
}

function formatDate(d) {
  if (!d) return '-';
  var dt = new Date(d);
  return dt.toLocaleDateString('pt-BR');
}

function formatCNPJ(v) {
  if (!v) return '-';
  var s = v.replace(/\D/g, '');
  if (s.length <= 11) {
    return s.replace(/(\d{3})(\d{3})(\d{3})(\d{2})/, '$1.$2.$3-$4');
  }
  return s.replace(/(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})/, '$1.$2.$3/$4-$5');
}

function showAlert(msg, type) {
  type = type || 'success';
  var container = document.getElementById('alertContainer');
  if (!container) {
    container = document.createElement('div');
    container.id = 'alertContainer';
    container.style.position = 'fixed';
    container.style.top = '20px';
    container.style.right = '20px';
    container.style.zIndex = '9999';
    document.body.appendChild(container);
  }
  var el = document.createElement('div');
  el.className = 'alert alert-' + type;
  el.textContent = msg;
  el.style.marginBottom = '8px';
  el.style.boxShadow = '0 4px 12px rgba(0,0,0,0.15)';
  container.appendChild(el);
  setTimeout(function() { el.remove(); }, 4000);
}
