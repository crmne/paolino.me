document.addEventListener('DOMContentLoaded', function() {
  'use strict';

  var topNav = document.querySelector('.top-nav');
  var menuOpenIcon = document.querySelector('.nav__icon-menu');
  var menuCloseIcon = document.querySelector('.nav__icon-close');
  var searchOpenIcon = document.querySelector('.nav__icon-search');
  var searchCloseIcon = document.querySelector('.search__close');
  var searchBox = document.querySelector('.search');
  var searchFocusTimer;

  function toggleClass(element, className, enabled) {
    if (element) element.classList.toggle(className, enabled);
  }

  function syncScrollLock() {
    var hasOverlay = (topNav && topNav.classList.contains('is-visible')) ||
      (searchBox && searchBox.classList.contains('is-visible'));
    document.body.classList.toggle('is-locked', Boolean(hasOverlay));
  }

  function menuOpen() {
    toggleClass(searchBox, 'is-visible', false);
    toggleClass(topNav, 'is-visible', true);
    syncScrollLock();
  }

  function menuClose() {
    toggleClass(topNav, 'is-visible', false);
    syncScrollLock();
  }

  function focusSearchInput() {
    var input = document.getElementById('js-search-input');
    if (!input) return;

    try {
      input.focus({ preventScroll: true });
    } catch (error) {
      input.focus();
    }

    searchFocusTimer = window.setTimeout(function() {
      if (searchBox && searchBox.classList.contains('is-visible')) input.focus();
    }, 150);
  }

  function searchOpen() {
    toggleClass(topNav, 'is-visible', false);
    toggleClass(searchBox, 'is-visible', true);
    syncScrollLock();
    if (window.initializeSiteSearch) window.initializeSiteSearch();
    focusSearchInput();
  }

  function searchClose() {
    window.clearTimeout(searchFocusTimer);
    toggleClass(searchBox, 'is-visible', false);
    syncScrollLock();
  }

  function clearSearch() {
    var input = document.getElementById('js-search-input');
    if (!input) return;
    input.value = '';
    input.dispatchEvent(new KeyboardEvent('keyup', { key: 'Backspace' }));
  }

  if (menuOpenIcon) menuOpenIcon.addEventListener('click', menuOpen);
  if (menuCloseIcon) menuCloseIcon.addEventListener('click', menuClose);
  if (searchOpenIcon) searchOpenIcon.addEventListener('click', searchOpen);
  if (searchCloseIcon) {
    searchCloseIcon.addEventListener('click', function() {
      clearSearch();
      searchClose();
    });
  }
  if (searchBox) {
    searchBox.addEventListener('click', function(event) {
      if (!event.target.closest('.search__box')) searchClose();
    });
  }
  document.addEventListener('keydown', function(event) {
    if (event.key === 'Escape' && searchBox && searchBox.classList.contains('is-visible')) {
      event.preventDefault();
      searchClose();
    }
  });

  var initialScroll = window.scrollY;
  var scrollTicking = false;
  var header = document.querySelector('.header');
  var topButton = document.querySelector('.top');

  function updateScrollUI() {
    var scroll = window.scrollY;
    toggleClass(header, 'is-hide', scroll > initialScroll && initialScroll > 70);
    toggleClass(topButton, 'is-active', scroll > window.innerHeight);
    initialScroll = scroll;
    scrollTicking = false;
  }

  window.addEventListener('scroll', function() {
    if (!scrollTicking) {
      window.requestAnimationFrame(updateScrollUI);
      scrollTicking = true;
    }
  }, { passive: true });

  if (topButton) {
    topButton.addEventListener('click', function() {
      window.scrollTo({ top: 0, behavior: 'smooth' });
    });
  }

  var grid = document.querySelector('.grid');
  var masonry = null;
  if (grid && window.Masonry) {
    masonry = new Masonry(grid, {
      itemSelector: '.grid__post',
      percentPosition: true
    });
    if (window.imagesLoaded) {
      imagesLoaded(grid).on('progress', function() { masonry.layout(); });
    }
  }

  var loadButton = document.querySelector('.load-more-posts');
  var loadMoreSection = document.querySelector('.load-more-section');

  function paginationPagePath(pageNumber) {
    return pagination_page_path_template.replace('__page__', pageNumber);
  }

  function resetLoadMoreButton() {
    if (!loadButton) return;
    loadButton.classList.remove('is-disabled');
    loadButton.setAttribute('aria-disabled', 'false');
    loadButton.href = pagination_next_url;
    loadButton.innerHTML = 'Load Posts <ion-icon name="arrow-down-outline"></ion-icon>';
  }

  if (loadButton) {
    loadButton.addEventListener('click', function(event) {
      event.preventDefault();
      var requestUrl = pagination_next_url || paginationPagePath(pagination_next_page_number);

      if (!requestUrl || !pagination_next_page_number) {
        toggleClass(loadMoreSection, 'hide', true);
        return;
      }

      loadButton.classList.add('is-disabled');
      loadButton.setAttribute('aria-disabled', 'true');
      loadButton.textContent = 'Loading...';

      fetch(requestUrl, { credentials: 'same-origin' })
        .then(function(response) {
          if (!response.ok) throw new Error('Could not load more posts');
          return response.text();
        })
        .then(function(html) {
          var page = new DOMParser().parseFromString(html, 'text/html');
          var posts = Array.from(page.querySelectorAll('.grid__post'));
          if (!posts.length) {
            toggleClass(loadMoreSection, 'hide', true);
            return;
          }

          posts.forEach(function(post) { grid.appendChild(post); });
          if (masonry) {
            masonry.appended(posts);
            if (window.imagesLoaded) {
              imagesLoaded(posts).on('progress', function() { masonry.layout(); });
            }
          }

          pagination_next_page_number += 1;
          pagination_next_url = paginationPagePath(pagination_next_page_number);
          if (pagination_next_page_number > pagination_available_pages_number) {
            toggleClass(loadMoreSection, 'hide', true);
          } else {
            resetLoadMoreButton();
          }
        })
        .catch(resetLoadMoreButton)
        .finally(function() {
          loadButton.classList.remove('is-disabled');
          loadButton.setAttribute('aria-disabled', 'false');
        });
    });
  }

  var home = document.querySelector('.home');
  if (home && !home.querySelector('section.author')) {
    var inner = home.querySelector('.container__inner');
    if (inner) inner.classList.add('without-author');
  }

  document.querySelectorAll('.post__content .highlighter-rouge .highlight, .page__content .highlighter-rouge .highlight').forEach(function(block) {
    if (block.querySelector('.code-copy-button')) return;
    var pre = block.querySelector('pre');
    if (!pre) return;

    var button = document.createElement('button');
    button.type = 'button';
    button.className = 'code-copy-button';
    button.setAttribute('aria-label', 'Copy code to clipboard');
    button.textContent = 'Copy';

    button.addEventListener('click', function() {
      copyTextToClipboard(pre.textContent.replace(/\n$/, ''))
        .then(function() { setCopiedState(button); })
        .catch(function() {
          button.textContent = 'Failed';
          button.disabled = true;
        });
    });
    block.appendChild(button);
  });

  function setCopiedState(button) {
    button.classList.add('is-copied');
    button.textContent = 'Copied';
    window.clearTimeout(button.copyTimeoutId);
    button.copyTimeoutId = window.setTimeout(function() {
      button.classList.remove('is-copied');
      button.textContent = 'Copy';
    }, 1600);
  }

  function copyTextToClipboard(value) {
    if (navigator.clipboard && window.isSecureContext) {
      return navigator.clipboard.writeText(value);
    }

    return new Promise(function(resolve, reject) {
      var textarea = document.createElement('textarea');
      textarea.value = value;
      textarea.setAttribute('readonly', '');
      textarea.style.position = 'fixed';
      textarea.style.top = '-9999px';
      document.body.appendChild(textarea);
      textarea.select();

      try {
        var copied = document.execCommand('copy');
        document.body.removeChild(textarea);
        copied ? resolve() : reject(new Error('Copy command failed'));
      } catch (error) {
        document.body.removeChild(textarea);
        reject(error);
      }
    });
  }
});
