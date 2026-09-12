// Light and dark themes. The inline script in <head> applies html[data-theme] before first
// paint; this keeps it in sync afterwards: the toggle, the system setting, and the demo.
const THEME_KEY = "vf-theme";
const darkQuery = matchMedia("(prefers-color-scheme: dark)");
const systemTheme = () => (darkQuery.matches ? "dark" : "light");
function storedTheme() {
  try {
    const saved = localStorage.getItem(THEME_KEY);
    return saved === "light" || saved === "dark" ? saved : null;
  } catch { return null; }
}
function applyTheme(theme) {
  document.documentElement.dataset.theme = theme;
  const meta = document.querySelector('meta[name="theme-color"]:not([media])');
  if (meta) meta.content = theme === "dark" ? "#0f1412" : "#f6f4f1";
  document.querySelectorAll("[data-theme-toggle]").forEach((button) => {
    button.setAttribute("aria-pressed", String(theme === "dark"));
    const label = theme === "dark" ? "Switch to the light theme" : "Switch to the dark theme";
    button.setAttribute("aria-label", label);
    button.title = label;
  });
  document.dispatchEvent(new CustomEvent("vf-theme", { detail: { theme } }));
}
function setTheme(theme) {
  // Choosing what the system already shows means "follow the system" from here on.
  try {
    if (theme === systemTheme()) localStorage.removeItem(THEME_KEY);
    else localStorage.setItem(THEME_KEY, theme);
  } catch { /* private mode: the choice lasts for this page only */ }
  applyTheme(theme);
}
function bindTheme() {
  applyTheme(storedTheme() || document.documentElement.dataset.theme || systemTheme());
  darkQuery.addEventListener("change", () => { if (!storedTheme()) applyTheme(systemTheme()); });
  document.querySelectorAll("[data-theme-toggle]").forEach((button) => {
    button.addEventListener("click", () => {
      setTheme(document.documentElement.dataset.theme === "dark" ? "light" : "dark");
    });
  });
  window.VortexTheme = { set: setTheme, get: () => document.documentElement.dataset.theme };
}

function bindNav() {
  const nav = document.querySelector("#nav, .nav");
  if (!nav) return;
  const sync = () => nav.classList.toggle("is-stuck", window.scrollY > 8);
  sync();
  window.addEventListener("scroll", sync, { passive: true });

  const toggle = nav.querySelector(".menu-toggle");
  const menu = nav.querySelector("#mobile-menu");
  if (!toggle || !menu) return;
  const close = () => {
    menu.hidden = true;
    toggle.setAttribute("aria-expanded", "false");
    toggle.textContent = "Menu";
  };
  toggle.addEventListener("click", () => {
    const open = toggle.getAttribute("aria-expanded") !== "true";
    menu.hidden = !open;
    toggle.setAttribute("aria-expanded", String(open));
    toggle.textContent = open ? "Close" : "Menu";
  });
  menu.addEventListener("click", (event) => {
    if (event.target.closest("a")) close();
  });
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && !menu.hidden) { close(); toggle.focus(); }
  });
  document.addEventListener("click", (event) => {
    if (!nav.contains(event.target)) close();
  });
  matchMedia("(min-width: 801px)").addEventListener("change", close);
}

function bindReveals() {
  const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;
  document.querySelectorAll("[data-reveal]").forEach((el) => {
    if (reduced) { el.classList.add("is-on"); return; }
    const io = new IntersectionObserver((entries) => {
      if (entries.some((entry) => entry.isIntersecting)) {
        el.classList.add("is-on");
        io.disconnect();
      }
    }, { threshold: 0.28 });
    io.observe(el);
  });
}

const REPO = "maheshauti96/VortexFlow";

function compareDotVersions(a, b) {
  const left = String(a).split(".").map((n) => parseInt(n, 10) || 0);
  const right = String(b).split(".").map((n) => parseInt(n, 10) || 0);
  const len = Math.max(left.length, right.length);
  for (let i = 0; i < len; i += 1) {
    const d = (left[i] || 0) - (right[i] || 0);
    if (d) return d;
  }
  return 0;
}

function bindDownload() {
  const links = document.querySelectorAll("[data-download]");
  const versions = document.querySelectorAll("[data-download-version]");
  if (!links.length && !versions.length) return;

  fetch(`https://api.github.com/repos/${REPO}/releases/latest`, {
    headers: { Accept: "application/vnd.github+json" },
  })
    .then((r) => (r.ok ? r.json() : Promise.reject(r.status)))
    .then((release) => {
      const dmg = (release.assets || []).find((a) => /\.dmg$/i.test(a.name));
      const tag = String(release.tag_name || release.name || "").replace(/^v/i, "");
      const pageTagEl = document.querySelector("[data-release-tag]");
      const pageTag = pageTagEl ? String(pageTagEl.textContent || "").replace(/^v/i, "") : "";
      const githubIsNewer = tag && pageTag && compareDotVersions(tag, pageTag) > 0;
      if (dmg && githubIsNewer) {
        links.forEach((a) => {
          a.href = dmg.browser_download_url;
          a.setAttribute("download", "");
        });
      }
      const size = dmg && githubIsNewer ? `${(dmg.size / 1048576).toFixed(1)} MB` : "";
      if (tag && githubIsNewer) document.querySelectorAll("[data-release-tag]").forEach((el) => { el.textContent = `v${tag}`; });
      if (!githubIsNewer) return;
      versions.forEach((el) => {
        const parts = [];
        if (tag) parts.push(`Version ${tag}`);
        if (size) parts.push(size);
        if (!parts.length) return;
        el.textContent = parts.join(" · ");
        el.hidden = false;
      });
    })
    .catch(() => {});
}

// Star count on GitHub buttons. Shown only once there is something to show; a
// freshly published repo saying "0" would be worse than saying nothing.
function bindStars() {
  const slots = document.querySelectorAll("[data-stars]");
  if (!slots.length) return;
  fetch(`https://api.github.com/repos/${REPO}`, {
    headers: { Accept: "application/vnd.github+json" },
  })
    .then((r) => (r.ok ? r.json() : Promise.reject(r.status)))
    .then((repo) => {
      const n = repo.stargazers_count | 0;
      if (n < 25) return;
      const text = n >= 1000 ? `${(n / 1000).toFixed(1).replace(/\.0$/, "")}k` : String(n);
      slots.forEach((el) => {
        el.textContent = text;
        el.setAttribute("aria-label", `${n} stars on GitHub`);
      });
    })
    .catch(() => {});
}

// Contributor avatars. Rendered only once there are enough faces for the strip to
// read as a community rather than a portrait.
function bindContributors() {
  const list = document.querySelector("[data-contributors]");
  if (!list) return;
  fetch(`https://api.github.com/repos/${REPO}/contributors?per_page=24`, {
    headers: { Accept: "application/vnd.github+json" },
  })
    .then((r) => (r.ok ? r.json() : Promise.reject(r.status)))
    .then((people) => {
      const humans = (people || []).filter((p) => p.type === "User");
      if (humans.length < 3) return;
      list.replaceChildren(...humans.map((p) => {
        const a = document.createElement("a");
        a.href = p.html_url;
        a.rel = "noopener";
        a.title = `${p.login} · ${p.contributions} commit${p.contributions === 1 ? "" : "s"}`;
        const img = document.createElement("img");
        img.src = `${p.avatar_url}&s=80`;
        img.alt = p.login;
        img.width = 40;
        img.height = 40;
        img.loading = "lazy";
        a.append(img);
        const li = document.createElement("li");
        li.append(a);
        return li;
      }));
      const wrap = list.closest("[data-contributors-wrap]");
      if (wrap) wrap.hidden = false;
    })
    .catch(() => {});
}

bindTheme();
bindNav();
bindReveals();
bindDownload();
bindStars();
bindContributors();
