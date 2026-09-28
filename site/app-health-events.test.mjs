import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import vm from 'node:vm';

const source = await readFile(new URL('./public/app-health-events.js', import.meta.url), 'utf8');

function createHarness({ flush = () => Promise.resolve(), setTimer = setTimeout, clearTimer = clearTimeout } = {}) {
  let clickHandler;
  const tracked = [];
  const navigation = [];
  const appHealth = {
    track: (name) => tracked.push(name),
    flush,
  };
  const context = {
    document: {
      addEventListener: (name, handler) => {
        assert.equal(name, 'click');
        clickHandler = handler;
      },
    },
    window: { appHealth, location: { assign: (url) => navigation.push(url) } },
    setTimeout: setTimer,
    clearTimeout: clearTimer,
    Promise,
  };
  vm.runInNewContext(source, context);
  return { clickHandler, tracked, navigation };
}

function clickEvent(overrides = {}) {
  const link = {
    tagName: 'A',
    href: 'https://storage.daddyrad.com/',
    getAttribute: (name) => (name === 'data-app-health-event' ? 'app.storage.opened' : null),
    hasAttribute: (name) => name === 'download' && Boolean(overrides.download),
    ...overrides.link,
  };
  const event = {
    target: { closest: () => link },
    button: 0,
    metaKey: false,
    ctrlKey: false,
    shiftKey: false,
    altKey: false,
    defaultPrevented: false,
    preventDefault() {
      this.defaultPrevented = true;
    },
    ...overrides,
  };
  delete event.link;
  delete event.download;
  return { event, link };
}

test('ordinary same-tab CTA waits for flush before navigating', async () => {
  let finishFlush;
  const harness = createHarness({
    flush: () => new Promise((resolve) => {
      finishFlush = resolve;
    }),
  });
  const { event } = clickEvent();

  const pending = harness.clickHandler(event);
  await Promise.resolve();
  assert.equal(event.defaultPrevented, true);
  assert.deepEqual(harness.tracked, ['app.storage.opened']);
  assert.deepEqual(harness.navigation, []);

  finishFlush();
  await pending;
  assert.deepEqual(harness.navigation, ['https://storage.daddyrad.com/']);
});

test('modified, new-tab, and download clicks keep browser navigation behavior', () => {
  const cases = [
    { metaKey: true },
    { button: 1 },
    { link: { getAttribute: (name) => (name === 'data-app-health-event' ? 'app.storage.opened' : '_blank') } },
    { download: true },
  ];

  for (const overrides of cases) {
    const harness = createHarness();
    const { event } = clickEvent(overrides);
    harness.clickHandler(event);
    assert.equal(event.defaultPrevented, false);
    assert.deepEqual(harness.tracked, ['app.storage.opened']);
    assert.deepEqual(harness.navigation, []);
  }
});

test('same-tab CTA navigates after the 4.5 second fallback if flush hangs', async () => {
  let fallback;
  let fallbackDelay;
  const harness = createHarness({
    flush: () => new Promise(() => {}),
    setTimer: (callback, delay) => {
      fallback = callback;
      fallbackDelay = delay;
      return 1;
    },
  });
  const { event } = clickEvent();
  const pending = harness.clickHandler(event);

  assert.equal(fallbackDelay, 4500);
  fallback();
  await pending;
  assert.deepEqual(harness.navigation, ['https://storage.daddyrad.com/']);
});
