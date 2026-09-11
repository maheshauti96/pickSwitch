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

bindNav();
bindReveals();
