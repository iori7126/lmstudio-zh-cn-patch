import fs from "node:fs";
import path from "node:path";
import process from "node:process";

const mapPath = process.argv[2];
const outputPath = process.argv[3];
const baseBundlePath = process.argv[4];
const deepBundlePath = process.argv[5];
if (!mapPath || !outputPath) {
  throw new Error(
    "Usage: node build_deep_overlay.mjs <map.json> <overlay.js> [base-bundle.js deep-bundle.js]",
  );
}
if ((baseBundlePath && !deepBundlePath) || (!baseBundlePath && deepBundlePath)) {
  throw new Error("base-bundle.js and deep-bundle.js must be provided together");
}

const translationMap = JSON.parse(fs.readFileSync(mapPath, "utf8"));
const mapJson = JSON.stringify(translationMap);
const source = String.raw`
;(() => {
  const translations = new Map(Object.entries(${mapJson}));
  const excluded = "script,style,noscript,code,pre,textarea,[contenteditable='true']";
  const attrs = ["aria-label", "title", "placeholder"];
  const normalize = (value) => value.replace(/\s+/g, " ").trim();
  const dynamic = (value) => {
    let match;
    if ((match = value.match(/^(\d+) days ago$/))) return match[1] + " 天前";
    if ((match = value.match(/^Show details for (.+)$/))) return "查看 " + match[1] + " 的详细信息";
    if ((match = value.match(/^Open Staff Pick page for (.+)$/))) return "打开 " + match[1] + " 的精选页面";
    if ((match = value.match(/^Navigate to step (\d+)$/))) return "转到第 " + match[1] + " 步";
    if ((match = value.match(/^Download(\d+(?:\.\d+)?\s+(?:GB|MB))$/))) return "下载 " + match[1];
    if ((match = value.match(/^Update(\d+(?:\.\d+)?\s+(?:GB|MB))$/))) return "更新 " + match[1];
    if ((match = value.match(/^(\d+(?:\.\d+)*) - Release notes$/))) return match[1] + " - 发行说明";
    return null;
  };
  const translate = (value) => {
    const normalized = normalize(value);
    return translations.get(normalized) ?? dynamic(normalized);
  };
  const translateText = (node) => {
    const parent = node.parentElement;
    if (!parent || parent.closest(excluded)) return;
    const replacement = translate(node.nodeValue ?? "");
    if (!replacement) return;
    const original = node.nodeValue;
    const leading = original.match(/^\s*/)?.[0] ?? "";
    const trailing = original.match(/\s*$/)?.[0] ?? "";
    node.nodeValue = leading + replacement + trailing;
  };
  const translateElement = (element) => {
    if (!(element instanceof Element) || element.closest(excluded)) return;
    for (const attr of attrs) {
      if (!element.hasAttribute(attr)) continue;
      const replacement = translate(element.getAttribute(attr) ?? "");
      if (replacement) element.setAttribute(attr, replacement);
    }
    for (const node of element.childNodes) {
      if (node.nodeType === Node.TEXT_NODE) translateText(node);
    }
  };
  const scan = (root) => {
    if (root.nodeType === Node.TEXT_NODE) {
      translateText(root);
      return;
    }
    if (!(root instanceof Element) && root !== document) return;
    if (root instanceof Element) translateElement(root);
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT);
    while (walker.nextNode()) {
      const node = walker.currentNode;
      if (node.nodeType === Node.TEXT_NODE) translateText(node);
      else translateElement(node);
    }
  };
  const start = () => {
    scan(document);
    const queued = new Set();
    let timer = null;
    const enqueue = (node) => {
      if (node?.isConnected) queued.add(node);
      if (timer !== null) return;
      timer = setTimeout(() => {
        timer = null;
        const candidates = [...queued].filter((node) => node.isConnected);
        queued.clear();
        const roots = candidates.filter((candidate, index) =>
          !candidates.some((other, otherIndex) =>
            index !== otherIndex &&
            other.nodeType === Node.ELEMENT_NODE &&
            other.contains(candidate)
          )
        );
        for (const root of roots) scan(root);
      }, 16);
    };
    const observer = new MutationObserver((records) => {
      for (const record of records) {
        if (record.type === "characterData" || record.type === "attributes") {
          enqueue(record.target);
        }
        for (const node of record.addedNodes) enqueue(node);
      }
    });
    observer.observe(document.documentElement, {
      subtree: true,
      childList: true,
      characterData: true,
      attributes: true,
      attributeFilter: attrs,
    });
    Object.defineProperty(window, "__LMSTUDIO_ZH_DEEP_PATCH__", {
      value: Object.freeze({ version: "0.4.20-1-deep-1", entries: translations.size }),
      enumerable: false,
      configurable: false,
      writable: false,
    });
  };
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", start, { once: true });
  } else {
    start();
  }
})();
`;

fs.writeFileSync(outputPath, source.trimStart(), "utf8");
if (baseBundlePath) {
  const baseBundle = fs.readFileSync(baseBundlePath, "utf8");
  fs.writeFileSync(deepBundlePath, `${baseBundle}\r\n${source.trimStart()}`, "utf8");
}
console.log(JSON.stringify({
  entries: Object.keys(translationMap).length,
  bytes: fs.statSync(outputPath).size,
  outputPath: path.resolve(outputPath),
  deepBundlePath: deepBundlePath ? path.resolve(deepBundlePath) : null,
}, null, 2));
