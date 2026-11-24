// interaction-audit.js: lists the clickable elements of the open page that do not look
// clickable. Run it in the page (agent-browser eval, obscura browser_evaluate, Playwright
// page.evaluate) after the screen has loaded. It returns JSON:
//   { checked, failures: [{ el, text, problems }], unreadableSheets }
// A problem is "cursor:<value>" (not a pointer) or "no-hover" (no :hover rule matches the
// element, its group or its peer). An empty failures list is the pass.
(() => {
  const CLICKABLE =
    'button, a[href], [role="button"], [role="link"], [role="tab"], [role="menuitem"], ' +
    'summary, label[for], input[type="button"], input[type="submit"], input[type="checkbox"], ' +
    'input[type="radio"], select, [onclick], [tabindex]:not([tabindex="-1"])';

  // Collect the selectors of every :hover rule, inside media, supports, layer and nested rules.
  const hoverSelectors = [];
  let unreadableSheets = 0;
  const walk = (rules, parentSelector) => {
    for (const rule of rules) {
      const sel = rule.selectorText;
      if (sel) {
        for (let part of sel.split(",")) {
          part = part.trim();
          if (parentSelector && part.includes("&"))
            part = part.replaceAll("&", parentSelector);
          if (part.includes(":hover")) hoverSelectors.push(part);
        }
      }
      if (rule.cssRules && rule.cssRules.length)
        walk(rule.cssRules, sel || parentSelector);
    }
  };
  for (const sheet of document.styleSheets) {
    try {
      walk(sheet.cssRules, null);
    } catch {
      unreadableSheets += 1;
    }
  }

  // A hover rule applies when its selector, with :hover removed, matches the element.
  // Tailwind group-hover compiles to `:is(:where(.group):hover *)`, which this also covers.
  const strip = (s) =>
    s
      .replace(/:hover/g, "")
      .replace(/::?[\w-]+(\([^)]*\))?$/, "")
      .trim() || "*";
  const hasHover = (el) =>
    hoverSelectors.some((s) => {
      try {
        return el.matches(strip(s));
      } catch {
        return false;
      }
    });

  const visible = (el) => {
    const r = el.getBoundingClientRect();
    const st = getComputedStyle(el);
    return (
      r.width > 0 &&
      r.height > 0 &&
      st.visibility !== "hidden" &&
      st.display !== "none"
    );
  };
  const describe = (el) => {
    const id = el.id ? `#${el.id}` : "";
    const cls =
      typeof el.className === "string" && el.className
        ? "." + el.className.trim().split(/\s+/).slice(0, 3).join(".")
        : "";
    return `${el.tagName.toLowerCase()}${id}${cls}`;
  };

  const failures = [];
  let checked = 0;
  for (const el of document.querySelectorAll(CLICKABLE)) {
    if (
      !visible(el) ||
      el.disabled ||
      el.getAttribute("aria-disabled") === "true"
    )
      continue;
    checked += 1;
    const problems = [];
    const cursor = getComputedStyle(el).cursor;
    const nativeCursor =
      el.matches('select, input[type="checkbox"], input[type="radio"]') &&
      cursor === "default";
    if (cursor !== "pointer" && !nativeCursor)
      problems.push(`cursor:${cursor}`);
    if (!hasHover(el)) problems.push("no-hover");
    if (problems.length)
      failures.push({
        el: describe(el),
        text: (el.innerText || el.getAttribute("aria-label") || "")
          .trim()
          .slice(0, 40),
        problems,
      });
  }
  return JSON.stringify({ checked, failures, unreadableSheets });
})();
