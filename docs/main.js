/* Caller: docs/index.html script tag. No existing main.js. No data I/O. User: "create a nice modern landing page, hosted on github pages." */
(() => {
  const keys = Array.from(document.querySelectorAll(".keyboard .key"));
  const wave = document.getElementById("wave");

  if (wave) {
    for (let i = 0; i < 48; i += 1) {
      const bar = document.createElement("span");
      bar.style.animationDelay = `${(i % 12) * 0.07}s`;
      wave.appendChild(bar);
    }
  }

  const pressRandom = () => {
    if (!keys.length) return;
    const key = keys[Math.floor(Math.random() * keys.length)];
    key.classList.add("pressed");
    window.setTimeout(() => key.classList.remove("pressed"), 90 + Math.random() * 80);
  };

  let typing = window.setInterval(pressRandom, 280);
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) {
      window.clearInterval(typing);
    } else {
      typing = window.setInterval(pressRandom, 280);
    }
  });

  const revealables = document.querySelectorAll(".how, .themes, .features, .footer-cta");
  revealables.forEach((el) => el.classList.add("reveal"));
  const io = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add("in");
          io.unobserve(entry.target);
        }
      });
    },
    { threshold: 0.18 }
  );
  revealables.forEach((el) => io.observe(el));

  const desk = document.querySelector(".desk");
  if (desk) {
    desk.addEventListener("pointermove", (event) => {
      const rect = desk.getBoundingClientRect();
      const x = (event.clientX - rect.left) / rect.width - 0.5;
      const y = (event.clientY - rect.top) / rect.height - 0.5;
      desk.style.transform = `perspective(900px) rotateX(${(-y * 4).toFixed(2)}deg) rotateY(${(x * 5).toFixed(2)}deg)`;
    });
    desk.addEventListener("pointerleave", () => {
      desk.style.transform = "";
    });
  }
})();
