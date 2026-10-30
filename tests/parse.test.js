// Runs the parser and geometry functions straight from Masks.qml, between the
// "// BEGIN parse" and "// END parse" markers, so the tests cover the code that
// runs on the TV.  node --test tests/parse.test.js
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const qml = fs.readFileSync(path.join(__dirname, "..", "screenmask", "Masks.qml"), "utf8");
const block = qml.slice(qml.indexOf("// BEGIN parse"), qml.indexOf("// END parse"));
const { parseConfig, geometry } = new Function(block + "\nreturn { parseConfig, geometry };")();

const SAMPLE = `# webos-screenmask config
enabled=1
revision=abc123
panel=3840x2160
preview_until=1700000000
mask m1 bottom 20 0 0 #000000
mask m2 left 8 300 600 #1A1a1A
mask bad1 middle 20 0 0 #000000
mask bad2 bottom 0 0 0 #000000
mask bad3 bottom 20 0 0 black
mask bad4 bottom -5 0 0 #000000
mask bad5 bottom 20 0
`;

test("parses settings and valid masks", () => {
  const config = parseConfig(SAMPLE);
  assert.equal(config.enabled, true);
  assert.equal(config.revision, "abc123");
  assert.equal(config.panelWidth, 3840);
  assert.equal(config.panelHeight, 2160);
  assert.equal(config.previewUntil, 1700000000);
  assert.deepEqual(config.masks, [
    { id: "m1", edge: "bottom", size: 20, start: 0, length: 0, color: "#000000" },
    { id: "m2", edge: "left", size: 8, start: 300, length: 600, color: "#1A1a1A" },
  ]);
});

test("skips invalid mask lines instead of failing", () => {
  assert.deepEqual(parseConfig(SAMPLE).masks.map((m) => m.id), ["m1", "m2"]);
});

test("a config without revision is rejected", () => {
  assert.equal(parseConfig("enabled=1\nmask m1 bottom 20 0 0 #000000\n"), null);
});

test("enabled is false unless exactly 1", () => {
  assert.equal(parseConfig("revision=r\nenabled=yes\n").enabled, false);
  assert.equal(parseConfig("revision=r\n").enabled, false);
});

test("an invalid panel keeps the 4K default", () => {
  const config = parseConfig("revision=r\npanel=0x0\n");
  assert.equal(config.panelHeight, 2160);
});

// 1920x1080 compositor on a 3840x2160 panel: ratio 0.5
const W = 1920, H = 1080, R = 0.5;
const box = (edge, size, start = 0, length = 0) => geometry({ edge, size, start, length }, R, W, H);

test("full bottom edge", () => {
  assert.deepEqual(box("bottom", 20), { x: 0, y: 1070, width: 1920, height: 10 });
});

test("odd sizes round up to whole compositor pixels", () => {
  assert.deepEqual(box("bottom", 7), { x: 0, y: 1076, width: 1920, height: 4 });
  assert.deepEqual(box("top", 1), { x: 0, y: 0, width: 1920, height: 1 });
});

test("segment on the left edge", () => {
  assert.deepEqual(box("left", 8, 300, 600), { x: 0, y: 150, width: 4, height: 300 });
});

test("full right edge", () => {
  assert.deepEqual(box("right", 10), { x: 1915, y: 0, width: 5, height: 1080 });
});

test("a segment past the edge end is clipped", () => {
  assert.deepEqual(box("top", 10, 3000, 2000), { x: 1500, y: 0, width: 420, height: 5 });
  assert.equal(box("bottom", 10, 5000).width, 0);
});

test("a mask never grows past the screen", () => {
  assert.equal(box("bottom", 5000).height, 1080);
  assert.equal(box("left", 5000).width, 1920);
});
