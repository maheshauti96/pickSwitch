const DMG =
  "https://github.com/maheshauti96/VortexFlow/releases/latest/download/Vortexflow-1.0.0.dmg";

function bindNav() {
  const nav = document.querySelector("#nav, .nav");
  if (!nav) return;
  const sync = () => nav.classList.toggle("is-stuck", window.scrollY > 8);
  sync();
  window.addEventListener("scroll", sync, { passive: true });
}

function bindDownloads() {
  document.querySelectorAll("[data-dmg]").forEach((link) => {
    link.setAttribute("href", DMG);
    link.addEventListener("click", () => {
      window.setTimeout(() => {
        window.location.href = "/thanks/";
      }, 400);
    });
  });
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

bindNav();
bindDownloads();
bindReveals();
bindHeroDemo();
