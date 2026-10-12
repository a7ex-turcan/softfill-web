/* Softfill website. Only what HTML cannot do on its own:
   - the language menu (a <details>, so it opens and closes without JavaScript) also closes on Escape, on a
     click outside it and when focus leaves it;
   - Home's hero video starts if autoplay alone didn't start it (the poster stays if the browser refuses,
     as Safari does in Low Power Mode), and its pause button appears once it plays (WCAG 2.2.2). Under
     reduced motion no video source matches, so nothing loads and no button shows;
   - Home's time-lapse card plays its replay from the design's own play button and scrubber. Without
     JavaScript the card shows the finished drawing and no button. */
(function () {
  'use strict';

  var menus = document.querySelectorAll('details[data-lang-menu]');
  Array.prototype.forEach.call(menus, function (menu) {
    // On the document, not the menu: Safari doesn't focus a <summary> on a mouse click, so focus may be on
    // the page while the menu is open.
    document.addEventListener('keydown', function (event) {
      if (event.key !== 'Escape' || !menu.open) return;
      var hadFocus = menu.contains(document.activeElement);
      menu.open = false;
      var summary = menu.querySelector('summary');
      if (hadFocus && summary) summary.focus();
    });
    document.addEventListener('pointerdown', function (event) {
      if (menu.open && !menu.contains(event.target)) menu.open = false;
    });
    menu.addEventListener('focusout', function (event) {
      if (menu.open && event.relatedTarget && !menu.contains(event.relatedTarget)) menu.open = false;
    });
  });

  var hero = document.querySelector('.cv-video');
  if (hero) {
    var start = function () {
      if (!hero.paused || !hero.currentSrc) return;
      var playing = hero.play();
      if (playing && playing.catch) playing.catch(function () {});
    };
    if (hero.readyState >= 3) start();
    else hero.addEventListener('canplay', start, { once: true });

    var toggle = document.querySelector('[data-hero-toggle]');
    if (toggle) {
      var sync = function () {
        if (!hero.currentSrc) return;
        toggle.hidden = false;
        toggle.classList.toggle('is-paused', hero.paused);
      };
      hero.addEventListener('play', sync);
      hero.addEventListener('pause', sync);
      if (!hero.paused) sync();
      toggle.addEventListener('click', function () {
        if (hero.paused) {
          var playing = hero.play();
          if (playing && playing.catch) playing.catch(function () {});
        } else {
          hero.pause();
        }
      });
    }
  }

  var card = document.querySelector('[data-timelapse]');
  if (card) {
    var video = card.querySelector('[data-timelapse-video]');
    var button = card.querySelector('[data-timelapse-play]');
    var time = card.querySelector('[data-timelapse-time]');
    var fill = card.querySelector('[data-timelapse-fill]');
    if (video && button && video.canPlayType('video/mp4')) {
      var show = function (seconds, fraction) {
        time.textContent = '0:0' + Math.min(6, Math.floor(seconds));
        fill.style.width = Math.round(fraction * 100) + '%';
      };
      button.hidden = false;
      button.addEventListener('click', function () {
        video.currentTime = 0;
        show(0, 0);
        card.classList.add('is-playing');
        button.hidden = true;
        var playing = video.play();
        if (playing && playing.catch) {
          playing.catch(function () {
            card.classList.remove('is-playing');
            button.hidden = false;
            show(6, 1);
          });
        }
      });
      video.addEventListener('timeupdate', function () {
        if (video.duration) show(video.currentTime, video.currentTime / video.duration);
      });
      video.addEventListener('ended', function () {
        show(6, 1);
        card.classList.remove('is-playing');
        card.classList.add('has-played');
        button.hidden = false;
        button.focus({ preventScroll: true });
      });
    }
  }
})();
