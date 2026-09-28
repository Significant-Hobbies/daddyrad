document.addEventListener('click', function (event) {
  var target = event.target;
  var link = target && target.closest ? target.closest('[data-app-health-event]') : null;
  var name = link && link.getAttribute('data-app-health-event');
  var appHealth = window.appHealth;
  if (!name || !appHealth || typeof appHealth.track !== 'function') return;

  appHealth.track(name);
  if (event.defaultPrevented) return;

  var targetName = (link.getAttribute('target') || '').toLowerCase();
  var sameTabAnchor =
    link.tagName === 'A' &&
    (!targetName || targetName === '_self') &&
    !link.hasAttribute('download') &&
    typeof link.href === 'string';
  var ordinaryClick =
    event.button === 0 && !event.metaKey && !event.ctrlKey && !event.shiftKey && !event.altKey;

  if (!sameTabAnchor || !ordinaryClick || typeof appHealth.flush !== 'function') {
    if (typeof appHealth.flush === 'function') void appHealth.flush();
    return;
  }

  event.preventDefault();
  var timeout;
  var sent = Promise.resolve().then(function () {
    return appHealth.flush();
  });
  var fallback = new Promise(function (resolve) {
    timeout = setTimeout(resolve, 4500);
  });

  return Promise.race([sent, fallback])
    .catch(function () {})
    .then(function () {
      clearTimeout(timeout);
      window.location.assign(link.href);
    });
});
