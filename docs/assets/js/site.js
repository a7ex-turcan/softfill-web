/* Softfill website. Only what HTML cannot do on its own: the language menu (a <details>, so it opens and
   closes without JavaScript) also closes on Escape, on a click outside it and when focus leaves it. */
(function () {
  'use strict';

  var menus = document.querySelectorAll('details[data-lang-menu]');
  Array.prototype.forEach.call(menus, function (menu) {
    menu.addEventListener('keydown', function (event) {
      if (event.key === 'Escape' && menu.open) {
        menu.open = false;
        var summary = menu.querySelector('summary');
        if (summary) summary.focus();
      }
    });
    document.addEventListener('pointerdown', function (event) {
      if (menu.open && !menu.contains(event.target)) menu.open = false;
    });
    menu.addEventListener('focusout', function (event) {
      if (menu.open && event.relatedTarget && !menu.contains(event.relatedTarget)) menu.open = false;
    });
  });

})();
