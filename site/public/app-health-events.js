document.addEventListener('click', function (event) {
  var target = event.target;
  var link = target && target.closest ? target.closest('[data-app-health-event]') : null;
  var name = link && link.getAttribute('data-app-health-event');
  if (name && window.appHealth && typeof window.appHealth.track === 'function') {
    window.appHealth.track(name);
  }
});
