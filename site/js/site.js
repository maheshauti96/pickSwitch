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
      if (dmg) {
        links.forEach((a) => {
          a.href = dmg.browser_download_url;
          a.setAttribute("download", "");
        });
      }
      const tag = String(release.tag_name || release.name || "").replace(/^v/i, "");
      const size = dmg ? `${(dmg.size / 1048576).toFixed(1)} MB` : "";
      if (tag) document.querySelectorAll("[data-release-tag]").forEach((el) => { el.textContent = `v${tag}`; });
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

bindNav();
bindReveals();
bindDownload();
bindStars();
bindContributors();
