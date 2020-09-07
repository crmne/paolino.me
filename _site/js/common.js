$(document).ready(function() {
  'use strict';


  var topNav = $(".top-nav"),
    menuOpenIcon = $(".nav__icon-menu"),
    menuCloseIcon = $(".ion-md-close"),
    menuList = $(".main-nav"),
    searchOpenIcon = $(".nav__icon-search"),
    searchCloseIcon = $(".search__close"),
    searchBox = $(".search");


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
    searchClose();
  });

  function menuOpen() {
    topNav.addClass("is-visible");
  }

  function menuClose() {
    topNav.removeClass("is-visible");
  }

  function searchOpen() {
    searchBox.addClass("is-visible");
  }

  function searchClose() {
    searchBox.removeClass("is-visible");
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

  $load_posts_button.click(function(e) {
    e.preventDefault();
    var loadMore = $('.load-more-section');
    var request_next_link = pagination_next_url.split('/page')[0] + '/page/' + pagination_next_page_number + '/';

    $.ajax({
      url: request_next_link,
      beforeSend: function() {
        $load_posts_button.text('Loading...');
      }
    }).done(function(data) {
      var posts = $('.grid__post', data);
      $('.grid').append(posts).masonry('appended', posts);
      $grid.imagesLoaded().progress(function() {
        $grid.masonry('layout');
      });

      if(! /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent) ) {
        setTimeout(function() {
          $('.fadein').addClass('inview');
        }, 50);
      }

      $load_posts_button.text('Load Posts ').append('<i class="ion ion-ios-arrow-down"></i>');
      pagination_next_page_number++;

      if (pagination_next_page_number > pagination_available_pages_number) {
        loadMore.addClass('hide');
      }
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

});