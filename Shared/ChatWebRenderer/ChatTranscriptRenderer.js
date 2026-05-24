(function () {
  "use strict";

  const bridge = window.webkit && window.webkit.messageHandlers
    ? window.webkit.messageHandlers.fluxHausChat
    : null;
  const transcript = document.getElementById("transcript");
  let lastMessageId = null;
  let userScrolledUp = false;

  function isNearBottom() {
    return window.innerHeight + window.scrollY >= document.documentElement.scrollHeight - 80;
  }

  window.addEventListener("scroll", () => {
    userScrolledUp = !isNearBottom();
  }, { passive: true });

  function post(message) {
    if (bridge) bridge.postMessage(message);
  }

  function escapeHTML(value) {
    return String(value ?? "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  function escapeAttribute(value) {
    return escapeHTML(value).replace(/`/g, "&#96;");
  }

  function safeURL(value) {
    try {
      const url = new URL(String(value));
      if (["http:", "https:", "mailto:"].includes(url.protocol)) return url.href;
    } catch (_) {}
    return null;
  }

  function inlineMarkdown(text) {
    let html = escapeHTML(text);
    html = html.replace(/`([^`]+)`/g, "<code>$1</code>");
    html = html.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
    html = html.replace(/\*([^*]+)\*/g, "<em>$1</em>");
    html = html.replace(/\[([^\]]+)\]\(([^)]+)\)/g, (_match, label, href) => {
      const url = safeURL(href);
      if (!url) return escapeHTML(label);
      return `<a href="${escapeAttribute(url)}" target="_blank" rel="noopener">${label}</a>`;
    });
    return html;
  }

  function tableRow(line, tag) {
    const cells = line.replace(/^\|/, "").replace(/\|$/, "").split("|");
    return `<tr>${cells.map((cell) => `<${tag}>${inlineMarkdown(cell.trim())}</${tag}>`).join("")}</tr>`;
  }

  function isTableSeparator(line) {
    const stripped = line.trim().replace(/^\|/, "").replace(/\|$/, "");
    if (!stripped.includes("-")) return false;
    return stripped.split("|").every((part) => /^:?-{3,}:?$/.test(part.trim()));
  }

  function markdownToHTML(markdown) {
    const lines = String(markdown ?? "").split(/\r?\n/);
    const blocks = [];
    let index = 0;

    while (index < lines.length) {
      const raw = lines[index];
      const trimmed = raw.trim();
      if (!trimmed) {
        index += 1;
        continue;
      }

      if (trimmed.startsWith("```")) {
        const language = escapeHTML(trimmed.slice(3).trim());
        const code = [];
        index += 1;
        while (index < lines.length && !lines[index].trim().startsWith("```")) {
          code.push(lines[index]);
          index += 1;
        }
        if (index < lines.length) index += 1;
        const label = language ? `<div class="code-language">${language}</div>` : "";
        blocks.push(`${label}<pre><code>${escapeHTML(code.join("\n"))}</code></pre>`);
        continue;
      }

      const heading = /^(#{1,6})\s+(.+)$/.exec(trimmed);
      if (heading) {
        const level = heading[1].length;
        blocks.push(`<h${level}>${inlineMarkdown(heading[2])}</h${level}>`);
        index += 1;
        continue;
      }

      if (/^([-*_])(\s*\1){2,}$/.test(trimmed)) {
        blocks.push("<hr>");
        index += 1;
        continue;
      }

      if (trimmed.startsWith(">")) {
        const quote = [];
        while (index < lines.length && lines[index].trim().startsWith(">")) {
          quote.push(lines[index].trim().replace(/^>\s?/, ""));
          index += 1;
        }
        blocks.push(`<blockquote>${inlineMarkdown(quote.join("\n"))}</blockquote>`);
        continue;
      }

      if (trimmed.includes("|") && index + 1 < lines.length && isTableSeparator(lines[index + 1])) {
        const header = tableRow(trimmed, "th");
        const rows = [];
        index += 2;
        while (index < lines.length && lines[index].trim().includes("|")) {
          rows.push(tableRow(lines[index].trim(), "td"));
          index += 1;
        }
        blocks.push(`<table><thead>${header}</thead><tbody>${rows.join("")}</tbody></table>`);
        continue;
      }

      if (/^[-*•]\s+/.test(trimmed) || /^\d+\.\s+/.test(trimmed)) {
        const ordered = /^\d+\.\s+/.test(trimmed);
        const items = [];
        while (index < lines.length) {
          const item = lines[index].trim();
          const match = ordered ? /^\d+\.\s+(.+)$/.exec(item) : /^[-*•]\s+(.+)$/.exec(item);
          if (!match) break;
          items.push(`<li>${inlineMarkdown(match[1])}</li>`);
          index += 1;
        }
        blocks.push(`<${ordered ? "ol" : "ul"}>${items.join("")}</${ordered ? "ol" : "ul"}>`);
        continue;
      }

      const paragraph = [];
      while (index < lines.length) {
        const next = lines[index].trim();
        if (!next || next.startsWith("```") || next.startsWith("#") || next.startsWith(">") ||
          /^[-*•]\s+/.test(next) || /^\d+\.\s+/.test(next)) {
          break;
        }
        paragraph.push(next);
        index += 1;
      }
      blocks.push(`<p>${inlineMarkdown(paragraph.join(" "))}</p>`);
    }

    return sanitizeHTML(blocks.join(""));
  }

  function sanitizeHTML(html) {
    const template = document.createElement("template");
    template.innerHTML = html;
    const allowedTags = new Set([
      "A", "BLOCKQUOTE", "BR", "CODE", "DIV", "EM", "H1", "H2", "H3", "H4",
      "H5", "H6", "HR", "LI", "OL", "P", "PRE", "SPAN", "STRONG", "TABLE",
      "TBODY", "TD", "TH", "THEAD", "TR", "UL"
    ]);
    const walker = document.createTreeWalker(template.content, NodeFilter.SHOW_ELEMENT);
    const removals = [];
    while (walker.nextNode()) {
      const node = walker.currentNode;
      if (!allowedTags.has(node.tagName)) {
        removals.push(node);
        continue;
      }
      for (const attribute of Array.from(node.attributes)) {
        const name = attribute.name.toLowerCase();
        if (name.startsWith("on")) {
          node.removeAttribute(attribute.name);
        } else if (name === "href") {
          const url = safeURL(attribute.value);
          if (url) {
            node.setAttribute("href", url);
            node.setAttribute("target", "_blank");
            node.setAttribute("rel", "noopener");
          } else {
            node.removeAttribute(attribute.name);
          }
        } else if (!["class", "target", "rel"].includes(name)) {
          node.removeAttribute(attribute.name);
        }
      }
    }
    removals.forEach((node) => node.replaceWith(document.createTextNode(node.textContent || "")));
    return template.innerHTML;
  }

  function textContent(message) {
    const content = escapeHTML(message.content);
    return content.replace(/\n/g, "<br>");
  }

  function messageContent(message) {
    if (message.role === "assistant" && !message.isProgress) return markdownToHTML(message.content);
    return textContent(message);
  }

  function imageGrid(images) {
    if (!images || images.length === 0) return "";
    const cls = images.length === 1 ? "one" : "many";
    return `<div class="image-grid ${cls}">${images.map((image) => {
      if (!/^data:image\/(jpeg|png|gif|webp|heic);base64,/.test(image.dataURL)) return "";
      return `<img class="attachment" alt="Attached image" src="${escapeAttribute(image.dataURL)}">`;
    }).join("")}</div>`;
  }

  function voiceButton(message) {
    if (!message.hasAudio) return "";
    const label = message.isPlaying ? "Stop" : "Play";
    const symbol = message.isPlaying ? "■" : "▶";
    return `<button class="voice-button" data-action="toggle-audio" data-message-id="${escapeAttribute(message.id)}">
      <span aria-hidden="true">${symbol}</span><span>${label}</span>
    </button>`;
  }

  function renderMessage(message) {
    const role = message.isProgress ? "progress" : message.role;
    return `<article class="row ${escapeAttribute(role)}" data-message-id="${escapeAttribute(message.id)}">
      <div class="bubble">
        ${imageGrid(message.images)}
        <div class="content">${messageContent(message)}</div>
        ${voiceButton(message)}
      </div>
    </article>`;
  }

  function typingIndicator() {
    return `<div class="typing" aria-live="polite">
      <span>Assistant is thinking</span>
      <span class="dots" aria-hidden="true"><span></span><span></span><span></span></span>
    </div>`;
  }

  function scrollToBottom() {
    window.requestAnimationFrame(() => window.scrollTo(0, document.documentElement.scrollHeight));
  }

  window.FluxHausChat = {
    setAppearance(appearance) {
      document.documentElement.dataset.scheme = appearance.scheme;
      document.documentElement.style.setProperty("--scale", String(appearance.scale || 1));
    },
    render(snapshot) {
      const nextLast = snapshot.messages[snapshot.messages.length - 1]?.id || null;
      const hasNewMessage = lastMessageId !== nextLast;
      const stick = !userScrolledUp || hasNewMessage;
      transcript.innerHTML = snapshot.messages.map(renderMessage).join("") +
        (snapshot.isLoading ? typingIndicator() : "");
      lastMessageId = nextLast;
      if (stick) {
        userScrolledUp = false;
        scrollToBottom();
      }
    }
  };

  document.addEventListener("click", (event) => {
    const audioButton = event.target.closest("[data-action='toggle-audio']");
    if (audioButton) {
      event.preventDefault();
      post({ type: "toggleAudio", messageId: audioButton.dataset.messageId });
      return;
    }
    const link = event.target.closest("a[href]");
    if (link) {
      event.preventDefault();
      post({ type: "openLink", url: link.href });
    }
  });

  window.addEventListener("load", () => post({ type: "ready" }));
})();
