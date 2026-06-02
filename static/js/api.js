var API = (function() {
  var BASE = 'https://api.projetosdinamicos.com.br/erp';

  function getToken() {
    return localStorage.getItem('erp_token');
  }

  function getHeaders() {
    var h = { 'Content-Type': 'application/json' };
    var t = getToken();
    if (t) h['Authorization'] = 'Bearer ' + t;
    return h;
  }

  function handleResponse(r) {
    if (!r.ok) {
      if (r.status === 401) {
        localStorage.removeItem('erp_token');
        localStorage.removeItem('erp_user');
        window.location.href = (typeof ROOT !== 'undefined' ? ROOT : '.') + '/login/';
        return;
      }
      return r.json().then(function(e) { throw new Error(e.error || 'Erro na requisição'); });
    }
    return r.json();
  }

  return {
    get: function(endpoint) {
      return fetch(BASE + '/' + endpoint, { headers: getHeaders() }).then(handleResponse);
    },
    post: function(endpoint, data) {
      return fetch(BASE + '/' + endpoint, {
        method: 'POST',
        headers: getHeaders(),
        body: JSON.stringify(data)
      }).then(handleResponse);
    },
    put: function(endpoint, data) {
      return fetch(BASE + '/' + endpoint, {
        method: 'PUT',
        headers: getHeaders(),
        body: JSON.stringify(data)
      }).then(handleResponse);
    },
    del: function(endpoint) {
      return fetch(BASE + '/' + endpoint, {
        method: 'DELETE',
        headers: getHeaders()
      }).then(handleResponse);
    },
    login: function(user, pass) {
      return fetch(BASE + '/auth/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ nome: user, senha: pass })
      }).then(function(r) {
        if (!r.ok) throw new Error('Credenciais inválidas');
        return r.json();
      }).then(function(d) {
        if (d.token) localStorage.setItem('erp_token', d.token);
        if (d.usuario) localStorage.setItem('erp_user', JSON.stringify(d.usuario));
        return d;
      });
    },
    logout: function() {
      localStorage.removeItem('erp_token');
      localStorage.removeItem('erp_user');
      window.location.href = (typeof ROOT !== 'undefined' ? ROOT : '.') + '/login/';
    },
    getUser: function() {
      try { return JSON.parse(localStorage.getItem('erp_user')); }
      catch(e) { return null; }
    },
    isAuthenticated: function() {
      return !!getToken();
    }
  };
})();
