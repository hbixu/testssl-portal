(function() {
  var COOKIE_NAME = 'theme';
  var COOKIE_MAX_AGE = 365 * 24 * 3600; // 1 year
  var html = document.documentElement;
  var toggle = document.getElementById('theme-toggle');

  function getTheme() {
    var match = document.cookie.match(new RegExp('(?:^|; )' + COOKIE_NAME + '=([^;]*)'));
    var value = (match ? match[1] : '').toLowerCase();
    return (value === 'light' || value === 'dark') ? value : (html.getAttribute('data-theme') || 'dark');
  }

  function setTheme(theme) {
    theme = theme === 'light' ? 'light' : 'dark';
    html.setAttribute('data-theme', theme);
    document.cookie = COOKIE_NAME + '=' + theme + '; path=/; max-age=' + COOKIE_MAX_AGE + '; SameSite=Lax';
    if (toggle) {
      toggle.setAttribute('aria-checked', theme === 'light' ? 'true' : 'false');
      var lightLabel = toggle.getAttribute('data-theme-light') || 'Light mode';
      var darkLabel = toggle.getAttribute('data-theme-dark') || 'Dark mode';
      toggle.setAttribute('aria-label', theme === 'light' ? lightLabel : darkLabel);
      toggle.setAttribute('title', theme === 'light' ? lightLabel : darkLabel);
    }
  }

  setTheme(getTheme());
  if (toggle) {
    toggle.addEventListener('click', function() {
      setTheme(getTheme() === 'dark' ? 'light' : 'dark');
    });
  }
})();
