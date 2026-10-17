  const names = { de: "Deutsch", es: "Español", en: "English", fr: "Français", it: "Italiano" };
  const hints = { de: "Ich höre zu …", es: "Te escucho …", en: "Listening …", fr: "J’écoute …", it: "Ti ascolto …" };

  // Restaurant dialog. Each line has the speaker's language and every translation.
  const script = [
    { src: "de", t: { de: "Hallo, einen Tisch für zwei, bitte.", es: "Hola, una mesa para dos, por favor.", en: "Hi, a table for two, please.", fr: "Bonjour, une table pour deux, s’il vous plaît.", it: "Salve, un tavolo per due, per favore." } },
    { src: "es", t: { de: "Natürlich, folgen Sie mir bitte hier entlang.", es: "Claro, síganme por aquí.", en: "Of course, follow me this way.", fr: "Bien sûr, suivez-moi par ici.", it: "Certo, seguitemi da questa parte." } },
    { src: "de", t: { de: "Können wir bitte die Speisekarte haben?", es: "¿Nos puede traer la carta, por favor?", en: "Could we have the menu, please?", fr: "Pourrions-nous avoir la carte, s’il vous plaît ?", it: "Potremmo avere il menù, per favore?" } },
    { src: "es", t: { de: "Natürlich. Möchten Sie in der Zwischenzeit etwas trinken?", es: "Por supuesto. ¿Algo de beber mientras tanto?", en: "Of course. Anything to drink in the meantime?", fr: "Bien sûr. Quelque chose à boire en attendant ?", it: "Certo. Qualcosa da bere nel frattempo?" } },
    { src: "de", t: { de: "Zwei Wasser und ein Glas Rotwein, bitte.", es: "Dos aguas y una copa de vino tinto, por favor.", en: "Two waters and a glass of red wine, please.", fr: "Deux eaux et un verre de vin rouge, s’il vous plaît.", it: "Due acque e un bicchiere di vino rosso, per favore." } },
    { src: "es", t: { de: "Perfekt, ich bringe es Ihnen sofort.", es: "Perfecto, ahora mismo se lo traigo.", en: "Perfect, I’ll bring it right away.", fr: "Parfait, je vous l’apporte tout de suite.", it: "Perfetto, ve lo porto subito." } },
    { src: "de", t: { de: "Das ist kein Problem, aber lern bitte demnächst Spanisch.", es: "No hay problema, pero aprende español pronto, por favor.", en: "No problem, but please learn Spanish soon.", fr: "Pas de problème, mais apprends l’espagnol bientôt.", it: "Nessun problema, ma impara presto lo spagnolo." } },
  ];

  let topLang = "de", bottomLang = "es";
  let turns = [];        // { src, t, live, shown }
  let step = 0, listening = true, timer = null;

  const paneTop = document.getElementById("paneTop");
  const paneBottom = document.getElementById("paneBottom");

  function renderPane(pane, reader) {
    // A side reads what the other side said, in its own language.
    const items = turns.filter(x => x.src !== reader);
    pane.innerHTML = "";
    if (!items.length) {
      const hint = document.createElement("div");
      hint.className = "hint";
      hint.textContent = hints[reader];
      pane.appendChild(hint);
      return;
    }
    const spacer = document.createElement("div");
    spacer.className = "spacer";
    pane.appendChild(spacer);
    items.forEach((x, i) => {
      const el = document.createElement("div");
      el.className = "line" + (i === items.length - 1 ? " newest" : "") + (x.live ? " live" : "");
      const words = x.t[reader].split(" ");
      el.textContent = x.live ? (words.slice(0, x.shown).join(" ") || "…") : x.t[reader];
      pane.appendChild(el);
    });
    pane.scrollTop = pane.scrollHeight;
  }

  function render() {
    document.getElementById("langTop").textContent = names[topLang];
    document.getElementById("langBottom").textContent = names[bottomLang];
    renderPane(paneTop, topLang);
    renderPane(paneBottom, bottomLang);
    document.getElementById("mic").classList.toggle("paused", !listening);
  }

  // Map the scripted de/es speakers onto whatever languages the sides use now.
  function nextTurn() {
    const line = script[step % script.length];
    step++;
    const src = line.src === "de" ? topLang : bottomLang;
    const turn = { src, t: line.t, live: true, shown: 0 };
    turns.push(turn);
    const target = src === topLang ? bottomLang : topLang;
    const total = line.t[target].split(" ").length;
    const tick = () => {
      if (!listening) { timer = setTimeout(tick, 200); return; }
      turn.shown++;
      render();
      if (turn.shown < total) {
        timer = setTimeout(tick, 230);
      } else {
        timer = setTimeout(() => { turn.live = false; render(); timer = setTimeout(nextTurn, 1600); }, 450);
      }
    };
    render();
    timer = setTimeout(tick, 400);
  }

  document.getElementById("swap").onclick = () => { [topLang, bottomLang] = [bottomLang, topLang]; render(); };
  document.getElementById("reset").onclick = () => { clearTimeout(timer); turns = []; step = 0; render(); timer = setTimeout(nextTurn, 1200); };
  document.getElementById("mic").onclick = () => { listening = !listening; render(); };

  const menu = document.getElementById("menu");
  function openMenu(side) {
    const current = side === "top" ? topLang : bottomLang;
    const other = side === "top" ? bottomLang : topLang;
    menu.innerHTML = "";
    Object.keys(names).forEach(code => {
      const b = document.createElement("button");
      b.textContent = names[code];
      if (code === current) b.className = "selected";
      b.onclick = (e) => {
        e.stopPropagation();
        if (code === other) { [topLang, bottomLang] = [bottomLang, topLang]; }
        else if (side === "top") { topLang = code; } else { bottomLang = code; }
        if (code !== other && code !== current) { clearTimeout(timer); turns = []; step = 0; timer = setTimeout(nextTurn, 1000); }
        menu.classList.remove("open");
        render();
      };
      menu.appendChild(b);
    });
    menu.classList.add("open");
  }
  document.getElementById("langTop").onclick = (e) => { e.stopPropagation(); openMenu("top"); };
  document.getElementById("langBottom").onclick = (e) => { e.stopPropagation(); openMenu("bottom"); };
  document.addEventListener("click", () => menu.classList.remove("open"));

  render();
  timer = setTimeout(nextTurn, 1200);
