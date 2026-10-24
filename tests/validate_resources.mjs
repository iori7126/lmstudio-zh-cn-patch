import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { spawnSync } from "node:child_process";

const repoRoot = path.resolve(process.argv[2] ?? path.join(path.dirname(new URL(import.meta.url).pathname), ".."));
const bundlePath = process.argv[3] ? path.resolve(process.argv[3]) : null;
const failures = [];
const checks = [];
const check = (name, ok, detail) => {
  checks.push({ name, ok: Boolean(ok), detail });
  if (!ok) failures.push(`${name}: ${detail}`);
};
function walk(root) {
  if (!fs.existsSync(root)) return [];
  return fs.readdirSync(root, { withFileTypes: true }).flatMap((entry) => {
    const full = path.join(root, entry.name);
    return entry.isDirectory() ? walk(full) : [full];
  });
}
function duplicateKeys(text) {
  const scopes = [];
  const duplicates = [];
  let quote = false;
  let escaped = false;
  for (let i = 0; i < text.length; i += 1) {
    const c = text[i];
    if (quote) {
      if (escaped) escaped = false;
      else if (c === "\\") escaped = true;
      else if (c === '"') quote = false;
      continue;
    }
    if (c === '"') {
      const start = i;
      let value = "";
      let innerEscaped = false;
      i += 1;
      for (; i < text.length; i += 1) {
        const ch = text[i];
        if (innerEscaped) { value += ch; innerEscaped = false; }
        else if (ch === "\\") { value += ch; innerEscaped = true; }
        else if (ch === '"') break;
        else value += ch;
      }
      let next = i + 1;
      while (/\s/.test(text[next] ?? "")) next += 1;
      if (text[next] === ":" && scopes.length > 0) {
        const scope = scopes[scopes.length - 1];
        if (scope.has(value)) duplicates.push(`${value}@${start}`);
        scope.add(value);
      }
      continue;
    }
    if (c === "{") scopes.push(new Set());
    if (c === "}") scopes.pop();
  }
  return duplicates;
}
function placeholders(value) {
  return typeof value === "string"
    ? [...value.matchAll(/\{\{[^{}]+\}\}|%[sd]|<customlink>/g)].map((m) => m[0]).sort()
    : [];
}
function leaves(value, prefix = "") {
  if (!value || typeof value !== "object") return [];
  return Object.entries(value).flatMap(([key, child]) => {
    const full = prefix ? `${prefix}.${key}` : key;
    return child && typeof child === "object" && !Array.isArray(child)
      ? leaves(child, full)
      : [[full, child]];
  });
}
function sha256(file) {
  return crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex").toUpperCase();
}

for (const file of walk(repoRoot).filter((item) => item.endsWith(".json") && !item.includes(`${path.sep}.git${path.sep}`))) {
  const relative = path.relative(repoRoot, file);
  const text = fs.readFileSync(file, "utf8");
  let parsed;
  try { parsed = JSON.parse(text); check(`JSON parse ${relative}`, true, "valid"); }
  catch (error) { check(`JSON parse ${relative}`, false, error.message); continue; }
  const duplicates = duplicateKeys(text);
  check(`JSON duplicate keys ${relative}`, duplicates.length === 0, duplicates.join(", "));
  if (!relative.startsWith(`payload${path.sep}`)) continue;
  const baseFile = path.join(repoRoot, "baseline", "zh-CN", path.basename(file));
  if (!fs.existsSync(baseFile)) continue;
  const base = JSON.parse(fs.readFileSync(baseFile, "utf8"));
  const baseLeaves = new Map(leaves(base));
  for (const [key, value] of leaves(parsed)) {
    if (!baseLeaves.has(key)) continue;
    const before = placeholders(baseLeaves.get(key));
    const after = placeholders(value);
    check(`Placeholder ${path.basename(file)}:${key}`, before.every((item) => after.includes(item)), `${before.join(",")} -> ${after.join(",")}`);
  }
}

const profiles = walk(path.join(repoRoot, "versions"))
  .filter((file) => file.endsWith("profile.json"))
  .map((file) => JSON.parse(fs.readFileSync(file, "utf8")));
check("Version profile count", profiles.length === 2, `${profiles.length}`);
check("Version profile IDs", new Set(profiles.map((item) => item.profileId)).size === profiles.length, profiles.map((item) => item.profileId).join(","));
for (const profile of profiles) {
  check(`Original SHA ${profile.version}`, /^[A-F0-9]{64}$/i.test(profile.originalSha256), profile.originalSha256);
  check(`Patched SHA ${profile.version}`, /^[A-F0-9]{64}$/i.test(profile.patchedSha256), profile.patchedSha256);
  check(`Overlay ${profile.version}`, fs.existsSync(path.join(repoRoot, profile.overlayPath)), profile.overlayPath);
  check(`Baseline ${profile.version}`, fs.existsSync(path.join(repoRoot, profile.baselineRoot)), profile.baselineRoot);
  check(`Payload ${profile.version}`, fs.existsSync(path.join(repoRoot, profile.payloadRoot)), profile.payloadRoot);
  const syntax = spawnSync(process.execPath, ["--check", path.join(repoRoot, profile.overlayPath)], { encoding: "utf8" });
  check(`Overlay syntax ${profile.version}`, syntax.status === 0, syntax.stderr || syntax.stdout);
}
const hashes = profiles.flatMap((item) => [item.originalSha256, item.patchedSha256]).map((item) => item.toUpperCase());
check("Version SHA uniqueness", new Set(hashes).size === hashes.length, hashes.join(","));
const map = JSON.parse(fs.readFileSync(path.join(repoRoot, "source", "deep-ui-zh-CN.json"), "utf8"));
check("Deep mapping count", Object.keys(map).length === 227, `${Object.keys(map).length}`);
const newMap = JSON.parse(fs.readFileSync(path.join(repoRoot, "source", "deep-ui-zh-CN-0.4.26.json"), "utf8"));
check("0.4.26 deep mapping count", Object.keys(newMap).length === 266, `${Object.keys(newMap).length}`);
const builder = spawnSync(process.execPath, ["--check", path.join(repoRoot, "source", "build_deep_overlay.mjs")], { encoding: "utf8" });
check("Overlay builder syntax", builder.status === 0, builder.stderr || builder.stdout);

if (bundlePath) {
  check("Bundle exists", fs.existsSync(bundlePath), bundlePath);
  if (fs.existsSync(bundlePath)) {
    const profile = profiles.find((item) => item.version === "0.4.26+4");
    const actual = sha256(bundlePath);
    check("0.4.26 original bundle hash", actual === profile.originalSha256, `${actual} != ${profile.originalSha256}`);
    const text = fs.readFileSync(bundlePath, "utf8");
    const expected = [
      ["chat", "modelLoaderPlaceholder", "Select a model to load"],
      ["config", "noInstanceSelected", "No model instance selected"],
      ["developer", "tabs/server", "Local Server"],
      ["models", "pageTitle", "My Models"],
      ["settings", "settingsDialogTitle", "App Settings"],
      ["shared", "copyLmStudioLinkButton/toolTip", "Copy Model Download Link"],
    ];
    for (const [name, key, value] of expected) check(`English locale ${name}`, text.includes(`"${key}":"${value}"`), `${key}=${value}`);
    const config = JSON.parse(fs.readFileSync(path.join(repoRoot, "payload", "zh-CN", "config.json"), "utf8"));
    for (const key of [
      "llm.load.mlx.autoFit/title", "llm.load.mlx.autoFit/subTitle",
      "llm.load.yuzu.autoFit/title", "llm.load.yuzu.autoFit/subTitle",
      "llm.load.mlx.diskCache/title", "llm.load.mlx.diskCache/subTitle",
    ]) check(`Payload key ${key}`, Object.hasOwn(config, key), key);
  }
}

console.log(JSON.stringify({ ok: failures.length === 0, checks, failures }, null, 2));
if (failures.length) process.exit(1);
