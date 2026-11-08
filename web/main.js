// 8GB Vibe - nút chép SHA-256, bảng RAM mở một dòng, hiện dần khi cuộn. Trang vẫn dùng được khi tắt JS.
(function () {
  document.querySelectorAll('[data-chep]').forEach(function (nut) {
    nut.addEventListener('click', function () {
      var nguon = document.querySelector('[data-pb="' + nut.getAttribute('data-chep') + '"]');
      if (!nguon || !navigator.clipboard) return;
      navigator.clipboard.writeText(nguon.textContent.trim()).then(function () {
        var cu = nut.textContent;
        nut.textContent = 'Đã chép';
        setTimeout(function () { nut.textContent = cu; }, 1500);
      });
    });
  });

  // Bảng RAM: mở dòng này thì đóng dòng khác
  var dong = document.querySelectorAll('.dong-ram');
  dong.forEach(function (d) {
    d.addEventListener('toggle', function () {
      if (d.open) dong.forEach(function (k) { if (k !== d) k.open = false; });
    });
  });

  // Chuyển động: chỉ bật khi có IntersectionObserver và người dùng không tắt chuyển động
  if (!('IntersectionObserver' in window) || window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
  document.documentElement.classList.add('js');
  var chap = document.querySelector('.man-chap');
  if (chap) requestAnimationFrame(function () { setTimeout(function () { chap.classList.add('mo'); }, 120); });
  var chon = 'section h2, .o, .dong-ram, .buoc-lon li, .buoc-cai li, .khoi-ram span';
  var cac = Array.prototype.slice.call(document.querySelectorAll(chon)).filter(function (e) { return !e.closest('.hero'); });
  var nhom = new Map();
  cac.forEach(function (e) {
    e.classList.add('hien');
    var p = e.parentElement; var i = nhom.get(p) || 0; nhom.set(p, i + 1);
    e.style.transitionDelay = Math.min(i, 6) * 70 + 'ms';
  });
  var xem = new IntersectionObserver(function (ds) {
    ds.forEach(function (d) { if (d.isIntersecting) { d.target.classList.add('da-hien'); xem.unobserve(d.target); } });
  }, { rootMargin: '0px 0px 10% 0px' });
  cac.forEach(function (e) { xem.observe(e); });
  // Dự phòng: khi cuộn nhanh hay nhảy tới cuối trang, hiện mọi phần đã đi qua
  var hienHet = function () {
    var day = window.scrollY + window.innerHeight * 1.1;
    cac.forEach(function (e) { if (!e.classList.contains('da-hien') && e.getBoundingClientRect().top + window.scrollY < day) e.classList.add('da-hien'); });
  };
  window.addEventListener('scroll', hienHet, { passive: true });
  window.addEventListener('hashchange', hienHet);
})();
