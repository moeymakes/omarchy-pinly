// Run with: node --test tests/*.test.mjs
import { test } from "node:test"
import assert from "node:assert/strict"
import { createRequire } from "node:module"

const require = createRequire(import.meta.url)
const h = require("../help.js")

test("help: every shortcut is a key and a description, and every guide section has text", () => {
  assert.ok(h.shortcuts.length >= 5)
  for (const sec of h.shortcuts) {
    assert.ok(sec.title && sec.items.length > 0, sec.title)
    for (const it of sec.items) assert.ok(it.length === 2 && it[0] && it[1], JSON.stringify(it))
  }
  for (const sec of h.guide) assert.ok(sec.title && sec.body.length > 0 && sec.body.every(p => p.length > 20), sec.title)
  // The panel's own keys are listed, so the help documents how to reopen it.
  assert.ok(h.shortcuts.some(s => s.items.some(i => i[0].includes("F1"))))
})
