function bindNav() {
  const nav = document.querySelector("#nav, .nav");
  if (!nav) return;
  const sync = () => nav.classList.toggle("is-stuck", window.scrollY > 8);
  sync();
  window.addEventListener("scroll", sync, { passive: true });
}

function bindReveals() {
  const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;
  document.querySelectorAll("[data-reveal]").forEach((el) => {
    if (reduced) {
      el.classList.add("is-on");
      return;
    }
    const io = new IntersectionObserver((es) => {
      if (es.some((e) => e.isIntersecting)) {
        el.classList.add("is-on");
        io.disconnect();
      }
    }, { threshold: 0.28 });
    io.observe(el);
  });
}

function bindHeroDemo() {
  const screen = document.querySelector(".demo-screen");
  if (!screen) return;
  const cursor = screen.querySelector(".demo-cursor");
  const spiral = screen.querySelector("vortex-spiral");
  if (!cursor || !spiral) return;

  const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;
  let running = false;
  let timers = [];

  const wait = (ms) => new Promise((res) => {
    const t = setTimeout(res, reduced ? Math.min(ms, 60) : ms);
    timers.push(t);
  });
  const move = (x, y, ms = 850) => {
    cursor.style.transitionDuration = `${ms}ms`;
    cursor.style.left = `${x}%`;
    cursor.style.top = `${y}%`;
    return wait(ms);
  };

  async function cycle() {
    if (!running) return;
    spiral.hideSpiral();
    cursor.classList.remove("is-on", "is-click");
    await move(16, 76, 0);
    await wait(280);
    cursor.classList.add("is-on");
    await wait(220);
    await move(50, 50, 920);
    await wait(120);
    cursor.classList.add("is-click");
    await wait(180);
    spiral.style.left = "50%";
    spiral.style.top = "50%";
    spiral.showSpiral();
    await spiral.playScene("desk");
    await wait(220);
    cursor.classList.remove("is-click");
    await wait(1800);
    await move(50, 11, 520);
    await spiral.playScene("tab-search");
    await wait(2200);
    await spiral.playScene("web-search");
    await wait(2400);
    spiral.hideSpiral();
    cursor.classList.remove("is-on");
    await wait(700);
    if (running) cycle();
  }

  const start = () => {
    if (running) return;
    running = true;
    cycle();
  };
  const stop = () => {
    running = false;
    timers.forEach(clearTimeout);
    timers = [];
  };

  const boot = () => {
    if (reduced) {
      spiral.showSpiral();
      spiral.playScene("desk");
      return;
    }
    const io = new IntersectionObserver((es) => {
      if (es.some((e) => e.isIntersecting)) start();
      else stop();
    }, { threshold: 0.35 });
    io.observe(screen);
  };

  if (customElements.get("vortex-spiral")) boot();
  else customElements.whenDefined("vortex-spiral").then(boot);
}

// Progressive enhancement over GitHub Releases. Every download link already points at
// the releases page, which works with no script at all; this only upgrades it to the
// direct disk image and fills in the version. Anything that fails leaves the page as
// it was — including the API's unauthenticated rate limit, and the repo being private.
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
bindHeroDemo();
bindDownload();
bindStars();
bindContributors();
