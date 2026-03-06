(function() {
  function initCustomSelects() {
    var wraps = document.querySelectorAll('.custom-select-wrap');
    wraps.forEach(function(wrap) {
      var select = wrap.querySelector('select');
      var trigger = wrap.querySelector('.custom-select-trigger');
      var dropdown = wrap.querySelector('.custom-select-dropdown');
      if (!select || !trigger || !dropdown) return;

      function getSelectedText() {
        if (select.options.length === 0) return '';
        var idx = select.selectedIndex;
        if (idx < 0) idx = 0;
        return select.options[idx].text;
      }

      function buildOptions() {
        dropdown.innerHTML = '';
        for (var i = 0; i < select.options.length; i++) {
          var opt = select.options[i];
          var div = document.createElement('div');
          div.className = 'custom-select-option';
          div.setAttribute('role', 'option');
          div.setAttribute('aria-selected', opt.selected ? 'true' : 'false');
          div.textContent = opt.text;
          div.dataset.value = opt.value;
          div.addEventListener('click', function() {
            var v = this.dataset.value;
            select.value = v;
            trigger.textContent = getSelectedText();
            wrap.querySelectorAll('.custom-select-option').forEach(function(o) {
              o.setAttribute('aria-selected', o.dataset.value === v ? 'true' : 'false');
            });
            dropdown.setAttribute('hidden', '');
            trigger.setAttribute('aria-expanded', 'false');
            if (wrap.dataset.redirect === 'lang') {
              window.location.href = '?lang=' + encodeURIComponent(v);
            } else {
              select.dispatchEvent(new Event('change', { bubbles: true }));
            }
          });
          dropdown.appendChild(div);
        }
      }

      trigger.textContent = getSelectedText();
      if (!trigger.textContent && select.options.length > 0) trigger.textContent = select.options[0].text;

      trigger.addEventListener('click', function(e) {
        e.preventDefault();
        var isOpen = dropdown.getAttribute('hidden') === null;
        if (isOpen) {
          dropdown.setAttribute('hidden', '');
          trigger.setAttribute('aria-expanded', 'false');
        } else {
          dropdown.removeAttribute('hidden');
          trigger.setAttribute('aria-expanded', 'true');
        }
      });

      select.addEventListener('change', function() {
        trigger.textContent = getSelectedText();
        wrap.querySelectorAll('.custom-select-option').forEach(function(o) {
          o.setAttribute('aria-selected', o.dataset.value === select.value ? 'true' : 'false');
        });
      });

      document.addEventListener('click', function closeIfOutside(e) {
        if (dropdown.getAttribute('hidden') === null && !wrap.contains(e.target)) {
          dropdown.setAttribute('hidden', '');
          trigger.setAttribute('aria-expanded', 'false');
        }
      });

      document.addEventListener('keydown', function(e) {
        if (e.key === 'Escape' && dropdown.getAttribute('hidden') === null) {
          dropdown.setAttribute('hidden', '');
          trigger.setAttribute('aria-expanded', 'false');
        }
      });

      buildOptions();
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initCustomSelects);
  } else {
    initCustomSelects();
  }
})();
