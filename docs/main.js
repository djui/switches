(() => {
  // KeyboardEvent.code → Mechvibes ID (matches app convert map)
  const CODE_TO_MECH = {
    Escape: 1,
    Digit1: 2, Digit2: 3, Digit3: 4, Digit4: 5, Digit5: 6, Digit6: 7, Digit7: 8, Digit8: 9, Digit9: 10, Digit0: 11,
    Minus: 12, Equal: 13, Backspace: 14, Tab: 15,
    KeyQ: 16, KeyW: 17, KeyE: 18, KeyR: 19, KeyT: 20, KeyY: 21, KeyU: 22, KeyI: 23, KeyO: 24, KeyP: 25,
    BracketLeft: 26, BracketRight: 27, Enter: 28, ControlLeft: 29,
    KeyA: 30, KeyS: 31, KeyD: 32, KeyF: 33, KeyG: 34, KeyH: 35, KeyJ: 36, KeyK: 37, KeyL: 38,
    Semicolon: 39, Quote: 40, Backquote: 41, ShiftLeft: 42, Backslash: 43,
    KeyZ: 44, KeyX: 45, KeyC: 46, KeyV: 47, KeyB: 48, KeyN: 49, KeyM: 50,
    Comma: 51, Period: 52, Slash: 53, ShiftRight: 54, AltLeft: 56, Space: 57, CapsLock: 58,
    AltRight: 3640, MetaLeft: 3675, MetaRight: 3676,
    ArrowUp: 57416, ArrowLeft: 57419, ArrowRight: 57421, ArrowDown: 57424,
  };

  const LAYOUT = [
    [
      ["Escape", "esc", 1], ["Digit1", "1", 2], ["Digit2", "2", 3], ["Digit3", "3", 4], ["Digit4", "4", 5],
      ["Digit5", "5", 6], ["Digit6", "6", 7], ["Digit7", "7", 8], ["Digit8", "8", 9], ["Digit9", "9", 10],
      ["Digit0", "0", 11], ["Minus", "−", 12], ["Equal", "=", 13], ["Backspace", "delete", 14],
    ],
    [
      ["Tab", "tab", 15], ["KeyQ", "Q", 16], ["KeyW", "W", 17], ["KeyE", "E", 18], ["KeyR", "R", 19],
      ["KeyT", "T", 20], ["KeyY", "Y", 21], ["KeyU", "U", 22], ["KeyI", "I", 23], ["KeyO", "O", 24],
      ["KeyP", "P", 25], ["BracketLeft", "[", 26], ["BracketRight", "]", 27], ["Backslash", "\\", 43],
    ],
    [
      ["CapsLock", "caps", 58], ["KeyA", "A", 30], ["KeyS", "S", 31], ["KeyD", "D", 32], ["KeyF", "F", 33],
      ["KeyG", "G", 34], ["KeyH", "H", 35], ["KeyJ", "J", 36], ["KeyK", "K", 37], ["KeyL", "L", 38],
      ["Semicolon", ";", 39], ["Quote", "'", 40], ["Enter", "return", 28],
    ],
    [
      ["ShiftLeft", "shift", 42], ["KeyZ", "Z", 44], ["KeyX", "X", 45], ["KeyC", "C", 46], ["KeyV", "V", 47],
      ["Space", "", 57], ["KeyB", "B", 48], ["KeyN", "N", 49], ["KeyM", "M", 50], ["ShiftRight", "shift", 54],
    ],
  ];

  const FALLBACKS = [30, 31, 32, 57, 28, 14, 16]; // A S D space enter delete Q
  const DEMO_LIMITED = new Set(["Cherry MX Blue ABS"]);

  const state = {
    theme: "Cardboard",
    volume: 0.8,
    width: 0.7,
    pitch: 0.03,
    vvarDb: 1.5,
    upGainDb: -4,
    headphones: false,
    paused: false,
    ignoreRepeat: true,
    audioReady: false,
  };

  let ctx = null;
  let master = null;
  const cache = new Map(); // theme -> Map(mechId-phase -> AudioBuffer)
  const held = new Set();
  const keyEls = new Map();

  const $ = (id) => document.getElementById(id);
  const statusEl = $("audio-status");
  const meterL = $("meter-l");
  const meterR = $("meter-r");
  const keyboard = $("keyboard");

  function buildKeyboard() {
    keyboard.innerHTML = "";
    LAYOUT.forEach((row, rowIndex) => {
      const rowEl = document.createElement("div");
      rowEl.className = "k-row";
      rowEl.dataset.row = String(rowIndex + 1);
      const count = row.length;
      row.forEach(([code, label, mech], i) => {
        const btn = document.createElement("button");
        btn.type = "button";
        btn.className = "keycap" + (mech === 57 || mech === 28 ? " is-accent" : "");
        btn.textContent = label;
        btn.dataset.code = code;
        btn.dataset.mech = String(mech);
        btn.dataset.pan = String((i / Math.max(1, count - 1)) * 2 - 1);
        btn.setAttribute("aria-label", label || "space");
        btn.addEventListener("pointerdown", (e) => {
          e.preventDefault();
          ensureAudio().then(() => {
            pressVisual(code, true);
            play(mech, "down", Number(btn.dataset.pan));
          });
        });
        btn.addEventListener("pointerup", () => {
          pressVisual(code, false);
          play(mech, "up", Number(btn.dataset.pan));
        });
        btn.addEventListener("pointerleave", () => {
          if (btn.classList.contains("is-down")) {
            pressVisual(code, false);
            play(mech, "up", Number(btn.dataset.pan));
          }
        });
        rowEl.appendChild(btn);
        keyEls.set(code, btn);
      });
      keyboard.appendChild(rowEl);
    });
  }

  function pressVisual(code, down) {
    const el = keyEls.get(code);
    if (!el) return;
    el.classList.toggle("is-down", down);
  }

  function flashMeter(pan, gain) {
    const l = Math.max(0, Math.min(1, (1 - pan) * 0.5)) * gain;
    const r = Math.max(0, Math.min(1, (1 + pan) * 0.5)) * gain;
    meterL.style.width = `${Math.round(l * 100)}%`;
    meterR.style.width = `${Math.round(r * 100)}%`;
  }

  async function ensureAudio() {
    if (!ctx) {
      ctx = new (window.AudioContext || window.webkitAudioContext)();
      master = ctx.createGain();
      master.gain.value = state.volume * state.volume;
      master.connect(ctx.destination);
    }
    if (ctx.state === "suspended") await ctx.resume();
    state.audioReady = true;
    statusEl.textContent = "Live — click keys or type anywhere on this page.";
    statusEl.classList.add("is-live");
    await loadTheme(state.theme);
  }

  function themePath(theme, mech, phase) {
    return `audio/${encodeURIComponent(theme).replace(/%20/g, "%20")}/${mech}-${phase}.wav`;
  }

  async function fetchBuffer(url) {
    const res = await fetch(url);
    if (!res.ok) return null;
    const raw = await res.arrayBuffer();
    return await ctx.decodeAudioData(raw.slice(0));
  }

  async function loadTheme(theme) {
    if (!ctx) return;
    if (cache.has(theme)) return;
    const map = new Map();
    const ids = new Set();
    LAYOUT.flat().forEach(([, , mech]) => ids.add(mech));
    FALLBACKS.forEach((id) => ids.add(id));
    if (DEMO_LIMITED.has(theme)) {
      // Only extracted keys for MX Blue demo
      [1, 14, 16, 17, 18, 19, 28, 30, 31, 32, 33, 57].forEach((id) => ids.add(id));
    }
    await Promise.all(
      [...ids].flatMap((mech) =>
        ["down", "up"].map(async (phase) => {
          const buf = await fetchBuffer(themePath(theme, mech, phase));
          if (buf) map.set(`${mech}-${phase}`, buf);
        })
      )
    );
    cache.set(theme, map);
  }

  function resolveBuffer(themeMap, mech, phase) {
    const direct = themeMap.get(`${mech}-${phase}`);
    if (direct) return direct;
    for (const fb of FALLBACKS) {
      const b = themeMap.get(`${fb}-${phase}`) || themeMap.get(`${fb}-down`);
      if (b) return b;
    }
    return themeMap.values().next().value || null;
  }

  function play(mech, phase, panX) {
    if (!ctx || state.paused || !state.audioReady) return;
    const themeMap = cache.get(state.theme);
    if (!themeMap) return;
    const buffer = resolveBuffer(themeMap, mech, phase);
    if (!buffer) return;

    const src = ctx.createBufferSource();
    src.buffer = buffer;
    const pitchJitter = 1 + (Math.random() * 2 - 1) * state.pitch;
    src.playbackRate.value = pitchJitter;

    const gain = ctx.createGain();
    const dbJitter = (Math.random() * 2 - 1) * state.vvarDb;
    let amp = Math.pow(10, dbJitter / 20);
    if (phase === "up") amp *= Math.pow(10, state.upGainDb / 20);
    gain.gain.value = amp;

    const pan = ctx.createStereoPanner();
    const p = Math.max(-1, Math.min(1, panX * state.width));
    pan.pan.value = p;

    let node = src;
    node.connect(gain);
    node = gain;

    if (state.headphones) {
      const delay = ctx.createDelay(0.002);
      delay.delayTime.value = Math.abs(p) * 0.0007;
      const merger = ctx.createChannelMerger(2);
      const splitter = ctx.createChannelSplitter(2);
      const gL = ctx.createGain();
      const gR = ctx.createGain();
      gL.gain.value = p < 0 ? 1 : 0.85;
      gR.gain.value = p > 0 ? 1 : 0.85;
      node.connect(splitter);
      if (p < 0) {
        splitter.connect(delay, 0);
        delay.connect(gL);
        splitter.connect(gR, 1);
      } else {
        splitter.connect(gL, 0);
        splitter.connect(delay, 1);
        delay.connect(gR);
      }
      gL.connect(merger, 0, 0);
      gR.connect(merger, 0, 1);
      merger.connect(master);
    } else {
      node.connect(pan);
      pan.connect(master);
    }

    flashMeter(p, Math.min(1, amp * state.volume));
    src.start();
  }

  function onKeyDown(e) {
    if (e.target && ["INPUT", "SELECT", "TEXTAREA"].includes(e.target.tagName)) return;
    const mech = CODE_TO_MECH[e.code];
    if (mech == null) return;
    if (e.repeat && state.ignoreRepeat) return;
    if (held.has(e.code)) return;
    held.add(e.code);
    ensureAudio().then(() => {
      const el = keyEls.get(e.code);
      const pan = el ? Number(el.dataset.pan) : 0;
      pressVisual(e.code, true);
      play(mech, "down", pan);
    });
  }

  function onKeyUp(e) {
    const mech = CODE_TO_MECH[e.code];
    if (mech == null) return;
    held.delete(e.code);
    const el = keyEls.get(e.code);
    const pan = el ? Number(el.dataset.pan) : 0;
    pressVisual(e.code, false);
    if (state.audioReady) play(mech, "up", pan);
  }

  function bindControls() {
    $("enable-audio").addEventListener("click", () => {
      ensureAudio().then(() => keyboard.focus());
    });

    $("ctrl-theme").addEventListener("change", async (e) => {
      state.theme = e.target.value;
      syncThemeCards();
      await ensureAudio();
      await loadTheme(state.theme);
      // Preview a centered-ish key
      play(31, "down", 0);
      setTimeout(() => play(31, "up", 0), 90);
    });

    const bindRange = (id, apply, readout) => {
      $(id).addEventListener("input", (e) => {
        apply(Number(e.target.value));
        if (readout) readout();
      });
    };

    bindRange("ctrl-volume", (v) => {
      state.volume = v / 100;
      if (master) master.gain.setTargetAtTime(state.volume * state.volume, ctx.currentTime, 0.015);
      $("vol-readout").textContent = `${v}%`;
    });
    bindRange("ctrl-width", (v) => {
      state.width = v / 100;
      $("width-readout").textContent = `${v}%`;
    });
    bindRange("ctrl-pitch", (v) => {
      state.pitch = v / 100;
      $("pitch-readout").textContent = `±${v}%`;
    });
    bindRange("ctrl-vvar", (v) => {
      state.vvarDb = v / 10;
      $("vvar-readout").textContent = `±${state.vvarDb.toFixed(1)} dB`;
    });
    bindRange("ctrl-up", (v) => {
      state.upGainDb = v;
      $("up-readout").textContent = `${v} dB`;
    });

    $("ctrl-phones").addEventListener("change", (e) => {
      state.headphones = e.target.checked;
    });
    $("ctrl-pause").addEventListener("change", (e) => {
      state.paused = e.target.checked;
    });
    $("ctrl-repeat").addEventListener("change", (e) => {
      state.ignoreRepeat = e.target.checked;
    });

    document.querySelectorAll(".theme-card[data-theme]").forEach((card) => {
      card.addEventListener("click", async () => {
        state.theme = card.dataset.theme;
        $("ctrl-theme").value = state.theme;
        syncThemeCards();
        await ensureAudio();
        await loadTheme(state.theme);
        play(30, "down", -0.35);
        setTimeout(() => play(30, "up", -0.35), 80);
        setTimeout(() => play(31, "down", 0), 120);
        setTimeout(() => play(32, "down", 0.35), 200);
      });
    });
  }

  function syncThemeCards() {
    document.querySelectorAll(".theme-card[data-theme]").forEach((card) => {
      card.classList.toggle("is-active", card.dataset.theme === state.theme);
    });
  }

  function revealOnScroll() {
    const els = document.querySelectorAll(".how, .settings-tour, .themes, .features-extra, .footer-cta");
    els.forEach((el) => el.classList.add("reveal"));
    const io = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add("in");
            io.unobserve(entry.target);
          }
        });
      },
      { threshold: 0.12 }
    );
    els.forEach((el) => io.observe(el));
  }

  const desk = $("desk");
  if (desk) {
    desk.addEventListener("pointermove", (event) => {
      const rect = desk.getBoundingClientRect();
      const x = (event.clientX - rect.left) / rect.width - 0.5;
      const y = (event.clientY - rect.top) / rect.height - 0.5;
      desk.style.transform = `perspective(1000px) rotateX(${(-y * 3).toFixed(2)}deg) rotateY(${(x * 4).toFixed(2)}deg)`;
    });
    desk.addEventListener("pointerleave", () => {
      desk.style.transform = "";
    });
  }

  buildKeyboard();
  bindControls();
  revealOnScroll();
  window.addEventListener("keydown", onKeyDown);
  window.addEventListener("keyup", onKeyUp);
})();
