// The wiki's contents list: highlights the section you're reading, and the
// search box narrows the wiki to sections that mention every word typed.
// Without JavaScript the page is simply the whole wiki with working links.
(function () {
  const sections = Array.from(document.querySelectorAll(".prose > section[id]"));
  const links = new Map(
    Array.from(document.querySelectorAll("#toc-list a")).map((a) => [a.hash.slice(1), a])
  );
  const groups = Array.from(document.querySelectorAll("#toc-list .group"));
  const search = document.getElementById("guide-search");
  const empty = document.getElementById("no-results");
  const article = document.getElementById("wiki");

  // ---- Where am I ----
  let current = null;
  function setActive(id) {
    if (id === current) return;
    current = id;
    links.forEach((a, key) => {
      const on = key === id;
      a.classList.toggle("active", on);
      if (on) a.setAttribute("aria-current", "location");
      else a.removeAttribute("aria-current");
    });
  }

  if ("IntersectionObserver" in window) {
    const visible = new Set();
    const io = new IntersectionObserver(
      (entries) => {
        entries.forEach((e) => (e.isIntersecting ? visible.add(e.target) : visible.delete(e.target)));
        const first = sections.find((s) => visible.has(s));
        if (first) setActive(first.id);
      },
      { rootMargin: "-80px 0px -60% 0px" }
    );
    sections.forEach((s) => io.observe(s));
  }

  // ---- Search ----
  const text = new Map(sections.map((s) => [s, s.textContent.toLowerCase()]));

  function filter(query) {
    const words = query.toLowerCase().split(/\s+/).filter(Boolean);
    let shown = 0;
    sections.forEach((s) => {
      const hit = words.every((w) => text.get(s).includes(w));
      s.hidden = !hit;
      const link = links.get(s.id);
      if (link) link.parentElement.hidden = !hit;
      if (hit) shown++;
    });
    // A group label with nothing under it left is noise.
    groups.forEach((g) => {
      let el = g.nextElementSibling, any = false;
      while (el && !el.classList.contains("group")) { if (!el.hidden) any = true; el = el.nextElementSibling; }
      g.hidden = !any;
    });
    article.classList.toggle("filtered", words.length > 0);
    empty.classList.toggle("show", words.length > 0 && shown === 0);
  }

  search.addEventListener("input", () => filter(search.value));
  search.addEventListener("keydown", (e) => {
    if (e.key === "Escape") { search.value = ""; filter(""); }
    if (e.key === "Enter") {
      const first = sections.find((s) => !s.hidden);
      if (first) { first.scrollIntoView(); history.replaceState(null, "", "#" + first.id); }
    }
  });

  // "/" focuses search, as on most documentation sites.
  document.addEventListener("keydown", (e) => {
    if (e.key === "/" && document.activeElement !== search && !e.metaKey && !e.ctrlKey) {
      e.preventDefault();
      search.focus();
    }
  });

  // On a narrow screen the contents fold away after a choice.
  document.querySelectorAll("#toc-list a").forEach((a) =>
    a.addEventListener("click", () => {
      const d = a.closest("details");
      if (d && window.matchMedia("(max-width: 900px)").matches) d.open = false;
    })
  );
  if (window.matchMedia("(max-width: 900px)").matches) {
    const d = document.querySelector(".toc details");
    if (d) d.open = false;
  }
})();
