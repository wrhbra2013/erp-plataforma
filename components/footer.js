document.write('\
    </main>\
    <div class="status-bar">\
      <span><span class="status-dot online" id="statusDot"></span> <span id="statusText">API Conectada</span></span>\
      <span id="clockDisplay"></span>\
      <span style="margin-left:auto;">ERP Fiscal v1.0.0</span>\
    </div>\
  </div>\
</div>\
');

// User display
(function() {
  var user = API.getUser();
  var ud = document.getElementById('userDisplay');
  if (ud && user) ud.textContent = user.nome || user.email || 'Usuário';

  // Clock
  var clock = document.getElementById('clockDisplay');
  if (clock) {
    function updateClock() {
      clock.textContent = new Date().toLocaleString('pt-BR');
    }
    updateClock();
    setInterval(updateClock, 1000);
  }

  // API health check
  var statusDot = document.getElementById('statusDot');
  var statusText = document.getElementById('statusText');
  var apiStatusBadge = document.getElementById('apiStatus');

  function checkHealth() {
    API.get('health').then(function(d) {
      if (statusDot) statusDot.className = 'status-dot online';
      if (statusText) statusText.textContent = 'API Conectada';
      if (apiStatusBadge) { apiStatusBadge.className = 'badge badge-success'; apiStatusBadge.textContent = 'Conectado'; }
    }).catch(function() {
      if (statusDot) statusDot.className = 'status-dot offline';
      if (statusText) statusText.textContent = 'API Offline';
      if (apiStatusBadge) { apiStatusBadge.className = 'badge badge-danger'; apiStatusBadge.textContent = 'Offline'; }
    });
  }

  checkHealth();
  setInterval(checkHealth, 30000);
})();
