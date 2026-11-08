// 8GB Vibe - nút chép SHA-256. Trang vẫn dùng được khi tắt JS.
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
})();
