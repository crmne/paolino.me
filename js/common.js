$(document).ready(function() {
  'use strict';


  var topNav = $(".top-nav"),
    menuOpenIcon = $(".nav__icon-menu"),
    menuCloseIcon = $(".nav__icon-close"),
    menuList = $(".main-nav"),
    searchOpenIcon = $(".nav__icon-search"),
    searchCloseIcon = $(".search__close"),
    searchBox = $(".search"),
    body = $("body");


  /* =======================
  // Hide Header
  ======================= */
  header();
  function header() {
    var initialScroll;
    $(window).scroll(function () {
      var scroll = $(this).scrollTop();
      if (scroll > initialScroll && initialScroll > 70) {
        $('.header').addClass('is-hide');
      } else {
        $('.header').removeClass('is-hide');
      }
      initialScroll = scroll;
    });
  }


  /* =======================
  // Menu and Search
  ======================= */
  menuOpenIcon.click(function() {
    menuOpen();
  })

  menuCloseIcon.click(function () {
    menuClose();
  })

  searchOpenIcon.click(function () {
    searchOpen();
  });

  searchCloseIcon.click(function () {
    clearSearch();
    searchClose();
  });

  searchBox.click(function (event) {
    if (!$(event.target).closest(".search__box").length) {
      searchClose();
    }
  });

  function menuOpen() {
    searchBox.removeClass("is-visible");
    topNav.addClass("is-visible");
    syncScrollLock();
  }

  function menuClose() {
    topNav.removeClass("is-visible");
    syncScrollLock();
  }

  function searchOpen() {
    topNav.removeClass("is-visible");
    searchBox.addClass("is-visible");
    syncScrollLock();
    $("#js-search-input").trigger("focus");
  }

  function searchClose() {
    searchBox.removeClass("is-visible");
    syncScrollLock();
  }

  function clearSearch() {
    var searchInput = $("#js-search-input");
    searchInput.val("");
    searchInput.trigger("keyup");
  }

  function syncScrollLock() {
    var hasOverlay = topNav.hasClass("is-visible") || searchBox.hasClass("is-visible");
    body.toggleClass("is-locked", hasOverlay);
  }


  /* =======================
  // Masonry Grid Layout
  ======================= */
  var $grid = $('.grid').masonry({
    itemSelector: '.grid__post',
    percentPosition: true
  });

  $grid.imagesLoaded().progress(function () {
    $grid.masonry('layout');
  });


  // =====================
  // Ajax Load More
  // =====================
  var $load_posts_button = $('.load-more-posts');

  function resetLoadMoreButton() {
    $load_posts_button.text('Load Posts ').append('<ion-icon name="arrow-down-outline"></ion-icon>');
  }

  function paginationPagePath(pageNumber) {
    return pagination_page_path_template.replace('__page__', pageNumber);
  }

  $load_posts_button.click(function(e) {
    e.preventDefault();
    var loadMore = $('.load-more-section');
    var request_next_link = pagination_next_url || paginationPagePath(pagination_next_page_number);

    if (!request_next_link || !pagination_next_page_number) {
      loadMore.addClass('hide');
      return;
    }

    $.ajax({
      url: request_next_link,
      beforeSend: function() {
        $load_posts_button.prop('disabled', true);
        $load_posts_button.text('Loading...');
      }
    }).done(function(data) {
      var posts = $('.grid__post', data);

      if (!posts.length) {
        loadMore.addClass('hide');
        return;
      }

      $('.grid').append(posts).masonry('appended', posts);
      $grid.imagesLoaded().progress(function() {
        $grid.masonry('layout');
      });

      if(! /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent) ) {
        setTimeout(function() {
          $('.fadein').addClass('inview');
        }, 50);
      }

      pagination_next_page_number++;
      pagination_next_url = paginationPagePath(pagination_next_page_number);

      if (pagination_next_page_number > pagination_available_pages_number) {
        loadMore.addClass('hide');
      } else {
        resetLoadMoreButton();
      }
    }).fail(function() {
      resetLoadMoreButton();
    }).always(function() {
      $load_posts_button.prop('disabled', false);
    });
  });


  /* =======================
  // Responsive Videos
  ======================= */
  $(".post__content, .page__content").fitVids({
    customSelector: ['iframe[src*="ted.com"]', 'iframe[src*="player.twitch.tv"]', 'iframe[src*="facebook.com"]']
  });


  /* =======================
  // Zoom Image
  ======================= */
  $(".page img, .post img").attr("data-action", "zoom");
  $(".page a img, .post a img").removeAttr("data-action", "zoom");


  /* =================================
  // Fade In
  ================================= */
  if(! /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent) ) {
    $('.fadein').viewportChecker({
      classToAdd: 'inview',
      offset: 100
    });
  }


  /* ==================================
  // If the Author section is disabled
  =================================== */
  if (!$(".home section").hasClass("author")) {
    $(".home .container__inner").addClass("without-author");
  }


  /* =======================
  // Scroll Top Button
  ======================= */
  $(".top").click(function() {
    $("html, body")
      .stop()
      .animate({ scrollTop: 0 }, "slow", "swing");
  });
  $(window).scroll(function() {
    if ($(this).scrollTop() > $(window).height()) {
      $(".top").addClass("is-active");
    } else {
      $(".top").removeClass("is-active");
    }
  });


  /* =======================
  // Code Block Copy Button
  ======================= */
  initCodeBlockCopy();

  function initCodeBlockCopy() {
    var codeBlocks = document.querySelectorAll('.post__content .highlighter-rouge .highlight, .page__content .highlighter-rouge .highlight');

    codeBlocks.forEach(function(block) {
      if (block.querySelector('.code-copy-button')) return;

      var pre = block.querySelector('pre');
      if (!pre) return;

      var button = document.createElement('button');
      button.type = 'button';
      button.className = 'code-copy-button';
      button.setAttribute('aria-label', 'Copy code to clipboard');
      button.textContent = 'Copy';

      button.addEventListener('click', function() {
        var code = pre.textContent.replace(/\n$/, '');

        copyTextToClipboard(code)
          .then(function() {
            setCopiedState(button);
          })
          .catch(function() {
            button.textContent = 'Failed';
            button.disabled = true;
          });
      });

      block.appendChild(button);
    });
  }

  function setCopiedState(button) {
    button.classList.add('is-copied');
    button.textContent = 'Copied';

    clearTimeout(button.copyTimeoutId);
    button.copyTimeoutId = setTimeout(function() {
      button.classList.remove('is-copied');
      button.textContent = 'Copy';
    }, 1600);
  }

  function copyTextToClipboard(text) {
    if (navigator.clipboard && window.isSecureContext) {
      return navigator.clipboard.writeText(text);
    }

    return new Promise(function(resolve, reject) {
      var textarea = document.createElement('textarea');
      textarea.value = text;
      textarea.setAttribute('readonly', '');
      textarea.style.position = 'fixed';
      textarea.style.top = '-9999px';
      textarea.style.left = '-9999px';

      document.body.appendChild(textarea);
      textarea.focus();
      textarea.select();

      try {
        var copied = document.execCommand('copy');
        document.body.removeChild(textarea);

        if (!copied) {
          reject(new Error('Copy command failed'));
          return;
        }

        resolve();
      } catch (error) {
        document.body.removeChild(textarea);
        reject(error);
      }
    });
  }

});
