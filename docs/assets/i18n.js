/* Language switching for the Kurdistan ATM policy pages.
 *
 * Each page carries all three languages as sibling blocks; this shows one and
 * flips the document direction. No build step, no dependencies.
 *
 * Sorani is the default because that is what most of the app's users read.
 * The choice is remembered so someone following the privacy link from the app
 * does not have to reselect it on every page.
 */
(function () {
  'use strict';

  var LANGS = ['ckb', 'ar', 'en'];
  var RTL = { ckb: true, ar: true, en: false };
  var KEY = 'kurdistan-atm-lang';

  function stored() {
    try {
      return localStorage.getItem(KEY);
    } catch (e) {
      // Private browsing, or storage blocked entirely. Not a failure.
      return null;
    }
  }

  function remember(lang) {
    try {
      localStorage.setItem(KEY, lang);
    } catch (e) {
      /* ignore - the page still works, the choice just will not persist */
    }
  }

  function apply(lang) {
    if (LANGS.indexOf(lang) === -1) lang = 'ckb';

    document.documentElement.lang = lang;
    document.documentElement.dir = RTL[lang] ? 'rtl' : 'ltr';

    var blocks = document.querySelectorAll('.lang');
    for (var i = 0; i < blocks.length; i++) {
      var on = blocks[i].getAttribute('data-lang') === lang;
      blocks[i].classList.toggle('on', on);
      // Keep screen readers and find-in-page away from the hidden copies.
      if (on) {
        blocks[i].removeAttribute('hidden');
      } else {
        blocks[i].setAttribute('hidden', '');
      }
    }

    var buttons = document.querySelectorAll('.langs button');
    for (var j = 0; j < buttons.length; j++) {
      buttons[j].setAttribute(
        'aria-pressed',
        buttons[j].getAttribute('data-set') === lang ? 'true' : 'false'
      );
    }

    remember(lang);
  }

  function init() {
    var buttons = document.querySelectorAll('.langs button');
    for (var i = 0; i < buttons.length; i++) {
      buttons[i].addEventListener('click', function (event) {
        apply(event.currentTarget.getAttribute('data-set'));
      });
    }

    // Honour ?lang=en so the app can deep-link straight to the right version.
    var asked = new URLSearchParams(window.location.search).get('lang');
    apply(asked || stored() || 'ckb');
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
