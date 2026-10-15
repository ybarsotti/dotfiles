// Lists the visible elements a callout usually points at, with their box in
// CSS px relative to the viewport. With shoot.sh --full the viewport is the
// whole page, so the boxes are page coordinates. Run it through
// `agent-browser eval`.
// Set window.__BOX_SELECTOR before the call to list other elements.
(() => {
  const selector =
    window.__BOX_SELECTOR ||
    "h1,h2,h3,h4,button,a,input,select,textarea,label,[role=switch],[role=tab]," +
      "[aria-current],[data-testid],time,li,span.font-medium,span.rounded-full";
  const seen = new Set();
  const rows = [];
  for (const el of document.querySelectorAll(selector)) {
    const r = el.getBoundingClientRect();
    if (r.width < 2 || r.height < 2 || r.bottom < 0 || r.top > innerHeight)
      continue;
    const box = [r.left, r.top, r.right, r.bottom].map(Math.round);
    const text = (el.getAttribute("aria-label") || el.textContent || "")
      .replace(/\s+/g, " ")
      .trim()
      .slice(0, 60);
    const key = `${box}|${text}`;
    if (seen.has(key)) continue;
    seen.add(key);
    const testid = el.getAttribute("data-testid");
    rows.push(
      `${el.tagName.toLowerCase()}${testid ? `[${testid}]` : ""} "${text}" [${box.join(",")}]`,
    );
  }
  return rows.join("\n");
})();
