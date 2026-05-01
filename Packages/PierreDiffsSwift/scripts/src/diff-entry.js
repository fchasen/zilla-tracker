/**
 * @pierre/diffs bundle entry point for ClaudeCodeUI
 *
 * This file is bundled with esbuild and loaded into a WKWebView.
 * It exposes the @pierre/diffs library and a bridge for Swift communication.
 */

import { FileDiff, parseDiffFromFile } from '@pierre/diffs';

// Global state
let currentDiffInstance = null;
let currentTheme = 'pierre-dark';
let currentDiffStyle = 'split';
let currentOverflow = 'scroll';

/**
 * Sends a message to Swift via webkit message handler
 */
function postToSwift(type, payload = {}) {
  if (window.webkit?.messageHandlers?.diffBridge) {
    window.webkit.messageHandlers.diffBridge.postMessage({
      type,
      ...payload,
    });
  } else {
    console.warn('Swift message handler not available');
  }
}

/**
 * Gets the container element, creating it if necessary
 */
function getContainer() {
  let container = document.getElementById('diff-container');
  if (!container) {
    container = document.createElement('div');
    container.id = 'diff-container';
    document.body.appendChild(container);
  }
  return container;
}

/**
 * Detects the language from a filename
 */
function detectLanguage(fileName) {
  if (!fileName) return undefined;

  const ext = fileName.split('.').pop()?.toLowerCase();
  const langMap = {
    // Swift & Apple
    swift: 'swift',
    m: 'objective-c',
    mm: 'objective-c',
    h: 'c',

    // JavaScript ecosystem
    js: 'javascript',
    jsx: 'jsx',
    ts: 'typescript',
    tsx: 'tsx',
    mjs: 'javascript',
    cjs: 'javascript',

    // Python
    py: 'python',
    pyw: 'python',
    pyi: 'python',

    // Go
    go: 'go',

    // Rust
    rs: 'rust',

    // Java & JVM
    java: 'java',
    kt: 'kotlin',
    kts: 'kotlin',
    scala: 'scala',

    // C family
    c: 'c',
    cpp: 'cpp',
    cc: 'cpp',
    cxx: 'cpp',
    hpp: 'cpp',
    hxx: 'cpp',

    // Ruby
    rb: 'ruby',
    erb: 'erb',

    // PHP
    php: 'php',

    // Shell
    sh: 'bash',
    bash: 'bash',
    zsh: 'bash',
    fish: 'fish',

    // Data formats
    json: 'json',
    yaml: 'yaml',
    yml: 'yaml',
    toml: 'toml',
    xml: 'xml',
    plist: 'xml',

    // Web
    html: 'html',
    htm: 'html',
    css: 'css',
    scss: 'scss',
    sass: 'sass',
    less: 'less',

    // Database
    sql: 'sql',

    // Markdown & docs
    md: 'markdown',
    mdx: 'mdx',
    rst: 'rst',

    // Config
    dockerfile: 'dockerfile',
    graphql: 'graphql',
    gql: 'graphql',

    // Other
    zig: 'zig',
    lua: 'lua',
    r: 'r',
    ps1: 'powershell',
    psm1: 'powershell',
  };

  // Handle special filenames
  const lowerFileName = fileName.toLowerCase();
  if (lowerFileName === 'dockerfile') return 'dockerfile';
  if (lowerFileName === 'makefile') return 'makefile';
  if (lowerFileName.endsWith('.d.ts')) return 'typescript';

  return langMap[ext] || undefined;
}


/**
 * Recursively walks shadow roots starting from `root` and ensures each one
 * carries a `<style>` element marked with `markerAttr` containing `cssText`.
 * Pierre's diffs render inside a `<diffs-container>` web component with a
 * shadow DOM, so document-level CSS doesn't reach internal nodes. Per-root
 * <style> tags are how we override Pierre styles.
 */
function injectShadowStyle(root, markerAttr, cssText) {
  if (!root || !root.querySelectorAll) return;
  root.querySelectorAll('*').forEach((el) => {
    if (el.shadowRoot) {
      if (!el.shadowRoot.querySelector(`style[${markerAttr}]`)) {
        const s = document.createElement('style');
        s.setAttribute(markerAttr, '1');
        s.textContent = cssText;
        el.shadowRoot.appendChild(s);
      }
      injectShadowStyle(el.shadowRoot, markerAttr, cssText);
    }
  });
}

/**
 * On touch devices Pierre's hover-only gutter "+" affordance never appears,
 * because there's no `:hover` to trigger it. Force it visible so iOS users
 * can tap to start an inline comment.
 */
function applyTouchAffordances(root) {
  if (!root) return;
  const css = `
    @media (hover: none) and (pointer: coarse) {
      .gutter-utility-slot { opacity: 1 !important; }
    }
  `;
  injectShadowStyle(root, 'data-zilla-touch-affordances', css);
}

/**
 * Minimal markdown-ish renderer for inline-comment bodies. Supports
 * paragraphs, blockquotes, ATX headers, fenced code blocks, inline code,
 * markdown links, bold/italic/strike, plus a `<u>` passthrough used by the
 * Remarkup→CommonMark converter for underline.
 */
function renderInlineMarkdown(text) {
  if (!text) return '';
  const escapeHtml = (s) => s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
  const escapeAttr = (s) => s
    .replace(/&/g, '&amp;')
    .replace(/"/g, '&quot;');

  const lines = text.replace(/\r\n?/g, '\n').split('\n');
  const out = [];
  let para = [];
  let quote = [];
  let codeFence = null;
  let codeLang = '';
  let codeBuf = [];

  const flushPara = () => {
    if (para.length) {
      out.push('<p>' + para.map(processInline).join('<br>') + '</p>');
      para = [];
    }
  };
  const flushQuote = () => {
    if (quote.length) {
      out.push('<blockquote>' + quote.map(processInline).join('<br>') + '</blockquote>');
      quote = [];
    }
  };

  for (const line of lines) {
    const fenceMatch = line.match(/^\s*(```|~~~)(.*)$/);
    if (fenceMatch) {
      if (codeFence === null) {
        flushPara();
        flushQuote();
        codeFence = fenceMatch[1];
        codeLang = fenceMatch[2].trim();
      } else if (line.includes(codeFence)) {
        const langClass = codeLang ? ` class="language-${escapeAttr(codeLang)}"` : '';
        out.push(`<pre><code${langClass}>${escapeHtml(codeBuf.join('\n'))}</code></pre>`);
        codeFence = null;
        codeLang = '';
        codeBuf = [];
      }
      continue;
    }
    if (codeFence !== null) {
      codeBuf.push(line);
      continue;
    }
    const headerMatch = line.match(/^(#{1,6})\s+(.+)$/);
    if (headerMatch) {
      flushPara();
      flushQuote();
      const level = headerMatch[1].length;
      out.push(`<h${level}>${processInline(headerMatch[2])}</h${level}>`);
      continue;
    }
    if (line.startsWith('> ')) {
      flushPara();
      quote.push(line.slice(2));
      continue;
    }
    if (line.trim() === '') {
      flushPara();
      flushQuote();
      continue;
    }
    flushQuote();
    para.push(line);
  }
  if (codeFence !== null && codeBuf.length) {
    out.push(`<pre><code>${escapeHtml(codeBuf.join('\n'))}</code></pre>`);
  }
  flushPara();
  flushQuote();
  return out.join('');

  function processInline(line) {
    const codeSpans = [];
    const safe = [];
    let s = line;

    s = s.replace(/`([^`]+)`/g, (_m, c) => {
      codeSpans.push('<code>' + escapeHtml(c) + '</code>');
      return `CS${codeSpans.length - 1}`;
    });

    s = s.replace(/<u>([\s\S]*?)<\/u>/g, (_m, c) => {
      safe.push('<u>' + escapeHtml(c) + '</u>');
      return `SF${safe.length - 1}`;
    });

    s = s.replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, (_m, t, u) => {
      safe.push(`<a href="${escapeAttr(u)}">${escapeHtml(t)}</a>`);
      return `SF${safe.length - 1}`;
    });

    s = escapeHtml(s);

    s = s.replace(/\*\*([^*\n]+)\*\*/g, '<strong>$1</strong>');
    s = s.replace(/(^|[^*])\*([^*\n]+)\*/g, '$1<em>$2</em>');
    s = s.replace(/~~([^~\n]+)~~/g, '<del>$1</del>');

    s = s.replace(/CS(\d+)/g, (_m, i) => codeSpans[+i]);
    s = s.replace(/SF(\d+)/g, (_m, i) => safe[+i]);

    return s;
  }
}

/**
 * Wires up link clicks inside a body element so navigation flows through the
 * Swift bridge instead of WKWebView's default load.
 */
function attachLinkClickHandlers(root) {
  if (!root || !root.querySelectorAll) return;
  root.querySelectorAll('a[href]').forEach((a) => {
    a.addEventListener('click', (e) => {
      e.preventDefault();
      e.stopPropagation();
      const url = a.getAttribute('href') || '';
      postToSwift('linkClicked', { url });
    });
  });
}

/**
 * Creates a DOM element for an inline annotation (comment).
 * Called by @pierre/diffs renderAnnotation callback.
 */
function createAnnotationDOM(annotation) {
  const { metadata } = annotation;
  if (!metadata) return document.createElement('div');

  const container = document.createElement('div');
  container.className = 'pierre-annotation';
  container.dataset.annotationId = metadata.id || '';

  // The metadata may carry a thread of comments. When present, render each
  // in sequence as avatar + author + body rows. Otherwise fall back to the
  // single (author, body) on this metadata for backwards compatibility.
  const comments = (Array.isArray(metadata.comments) && metadata.comments.length > 0)
    ? metadata.comments
    : [{
        id: metadata.id || '',
        author: metadata.author,
        body: metadata.body,
        avatarURL: metadata.avatarURL,
        subtitle: metadata.subtitle,
        mode: metadata.mode,
      }];

  comments.forEach((comment, index) => {
    const isEditable = comment.mode === 'compose' || comment.mode === 'edit';
    const row = document.createElement('div');
    row.className = 'pierre-annotation-row';
    if (index > 0) row.classList.add('pierre-annotation-reply');
    if (isEditable) row.classList.add('pierre-annotation-editor');

    const content = document.createElement('div');
    content.className = 'pierre-annotation-content';

    const header = document.createElement('div');
    header.className = 'pierre-annotation-header';

    if (comment.author) {
      const authorSpan = document.createElement('span');
      authorSpan.className = 'pierre-annotation-author';
      authorSpan.textContent = comment.author;
      header.appendChild(authorSpan);
    }

    if (comment.subtitle) {
      const subtitleSpan = document.createElement('span');
      subtitleSpan.className = 'pierre-annotation-subtitle';
      subtitleSpan.textContent = comment.subtitle;
      header.appendChild(subtitleSpan);
    }

    if (index === 0 && !isEditable && metadata.deletable === true) {
      const deleteBtn = document.createElement('button');
      deleteBtn.className = 'pierre-annotation-delete';
      deleteBtn.textContent = '\u00D7';
      deleteBtn.title = 'Delete annotation';
      deleteBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        postToSwift('annotationDeleteRequested', {
          id: metadata.id || '',
          side: annotation.side || '',
          lineNumber: annotation.lineNumber || 0,
        });
      });
      header.appendChild(deleteBtn);
    }

    content.appendChild(header);

    if (isEditable) {
      const textarea = document.createElement('textarea');
      textarea.className = 'pierre-annotation-textarea';
      textarea.value = comment.body || '';
      textarea.placeholder = 'Leave a comment…';
      textarea.rows = 3;
      // Stop the parent click handler from firing when interacting with the
      // editor; otherwise typing/dragging selects the line behind us.
      textarea.addEventListener('mousedown', (e) => e.stopPropagation());
      textarea.addEventListener('click', (e) => e.stopPropagation());
      // Auto-grow with content.
      const autosize = () => {
        textarea.style.height = 'auto';
        textarea.style.height = (textarea.scrollHeight + 2) + 'px';
      };
      textarea.addEventListener('input', autosize);
      // ⌘↩ submits.
      textarea.addEventListener('keydown', (e) => {
        if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') {
          e.preventDefault();
          submit();
        } else if (e.key === 'Escape') {
          e.preventDefault();
          cancel();
        }
      });
      // Defer focus + autosize until DOM is in the document.
      requestAnimationFrame(() => {
        autosize();
        textarea.focus();
        const len = textarea.value.length;
        textarea.setSelectionRange(len, len);
      });
      content.appendChild(textarea);

      const actions = document.createElement('div');
      actions.className = 'pierre-annotation-actions';

      const cancelBtn = document.createElement('button');
      cancelBtn.className = 'pierre-annotation-button pierre-annotation-button-secondary';
      cancelBtn.textContent = 'Cancel';
      cancelBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        cancel();
      });

      const submitBtn = document.createElement('button');
      submitBtn.className = 'pierre-annotation-button pierre-annotation-button-primary';
      submitBtn.textContent = comment.mode === 'edit' ? 'Save' : 'Save Draft';
      submitBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        submit();
      });

      actions.appendChild(cancelBtn);
      actions.appendChild(submitBtn);
      content.appendChild(actions);

      const submit = () => {
        const body = textarea.value;
        if (!body.trim()) return;
        postToSwift('annotationDraftSubmitted', {
          annotationID: metadata.id || '',
          commentID: comment.id || '',
          body: body,
          side: annotation.side || '',
          lineNumber: annotation.lineNumber || 0,
        });
      };
      const cancel = () => {
        postToSwift('annotationDraftCancelled', {
          annotationID: metadata.id || '',
          commentID: comment.id || '',
          side: annotation.side || '',
          lineNumber: annotation.lineNumber || 0,
        });
      };
    } else {
      const body = document.createElement('div');
      body.className = 'pierre-annotation-body';
      body.innerHTML = renderInlineMarkdown(comment.body || '');
      attachLinkClickHandlers(body);
      content.appendChild(body);
    }

    row.appendChild(content);
    container.appendChild(row);
  });

  container.addEventListener('click', (e) => {
    e.stopPropagation();
    postToSwift('annotationClicked', {
      id: metadata.id || '',
      side: annotation.side || '',
      lineNumber: annotation.lineNumber || 0,
    });
  });

  return container;
}

/**
 * Bridge object exposed to Swift
 */
window.pierreBridge = {
  /**
   * Renders a diff from input data
   * @param {object|string} inputData - Diff data (object or JSON string)
   */
  renderDiff(inputData) {
    try {
      // Handle both object (from base64 decode) and string input
      const input = typeof inputData === 'string' ? JSON.parse(inputData) : inputData;

      const { oldFile, newFile, options = {} } = input;

      // Clean up previous instance
      if (currentDiffInstance) {
        currentDiffInstance.cleanUp();
        currentDiffInstance = null;
      }

      // Clear container
      const container = getContainer();
      container.innerHTML = '';
      applyTouchAffordances(document);

      // Update current settings
      if (options.theme) {
        currentTheme = typeof options.theme === 'string' ? options.theme : options.theme.dark;
      }
      if (options.diffStyle) {
        currentDiffStyle = options.diffStyle;
      }
      if (options.overflow) {
        currentOverflow = options.overflow;
      }

      // Detect languages if not specified
      const oldLang = oldFile.lang || detectLanguage(oldFile.name);
      const newLang = newFile.lang || detectLanguage(newFile.name);

      // Create file objects for @pierre/diffs
      const oldFileObj = {
        name: oldFile.name || 'old',
        contents: oldFile.contents || '',
        lang: oldLang,
      };

      const newFileObj = {
        name: newFile.name || 'new',
        contents: newFile.contents || '',
        lang: newLang,
      };

      // Create FileDiff instance
      currentDiffInstance = new FileDiff({
        theme: {
          dark: 'pierre-dark',
          light: 'pierre-light',
        },
        themeType: currentTheme.includes('light') ? 'light' : 'dark',
        diffStyle: currentDiffStyle,
        diffIndicators: 'bars',
        hunkSeparators: 'line-info',
        lineDiffType: 'word-alt',
        overflow: currentOverflow,
        enableLineSelection: options.enableLineSelection ?? true,
        // Show Pierre's built-in hover-add affordance — a "+" button that
        // appears in the gutter when the user hovers a line. Clicking it
        // routes through the same lineClicked event so Swift can open the
        // in-diff composer at that line.
        enableGutterUtility: true,
        renderAnnotation(annotation) {
          return createAnnotationDOM(annotation);
        },
        onLineClick: ({ lineNumber, side }) => {
          postToSwift('lineClicked', { lineNumber, side, lineY: 0, lineHeight: 22 });
        },
        onGutterUtilityClick: (range) => {
          if (!range) return;
          // For single-line clicks, range.start === range.end. For drag
          // selections, we anchor the comment at the start.
          postToSwift('lineClicked', {
            lineNumber: range.start,
            side: range.side || 'unified',
            lineY: 0,
            lineHeight: 22,
          });
        },
        onLineSelectionEnd: (range) => {
          if (range) {
            postToSwift('selectionChanged', {
              startLine: range.start,
              endLine: range.end,
              side: range.side,
            });
          }
        },
      });

      // Render the diff
      currentDiffInstance.render({
        oldFile: oldFileObj,
        newFile: newFileObj,
        containerWrapper: container,
        lineAnnotations: input.lineAnnotations || [],
      });

      postToSwift('ready');
    } catch (error) {
      console.error('Error rendering diff:', error);
      postToSwift('error', { message: error.message });
    }
  },

  /**
   * Sets the current theme
   * @param {string} theme - "dark", "light", or "system"
   */
  setTheme(theme) {
    if (!currentDiffInstance) return;

    let themeType;
    if (theme === 'system') {
      themeType = window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
    } else {
      themeType = theme;
    }

    currentTheme = themeType === 'dark' ? 'pierre-dark' : 'pierre-light';
    currentDiffInstance.setThemeType(themeType);
  },

  /**
   * Sets the diff style
   * @param {string} style - "split" or "unified"
   */
  setDiffStyle(style) {
    if (!currentDiffInstance) return;

    currentDiffStyle = style;
    currentDiffInstance.setOptions({
      ...currentDiffInstance.options,
      diffStyle: style,
    });
    currentDiffInstance.rerender();
  },

  /**
   * Sets the overflow mode (wrap or scroll)
   * @param {string} mode - "wrap" or "scroll"
   */
  setOverflow(mode) {
    if (!currentDiffInstance) return;

    currentOverflow = mode;
    currentDiffInstance.setOptions({
      ...currentDiffInstance.options,
      overflow: mode,
    });
    currentDiffInstance.rerender();
  },

  /**
   * Scrolls to a specific line number
   * @param {number} lineNumber - The line number to scroll to
   */
  scrollToLine(lineNumber) {
    const lineElement = document.querySelector(`[data-line-index="${lineNumber - 1}"]`);
    if (lineElement) {
      lineElement.scrollIntoView({ behavior: 'smooth', block: 'center' });
    }
  },

  /**
   * Gets the currently selected text
   * @returns {string} The selected text
   */
  getSelection() {
    return window.getSelection()?.toString() || '';
  },

  /**
   * Sets line annotations dynamically without full re-render
   * @param {object|string} annotationsData - Array of annotations (object or JSON string)
   */
  setAnnotations(annotationsData) {
    if (!currentDiffInstance) return;
    try {
      const annotations = typeof annotationsData === 'string'
        ? JSON.parse(annotationsData)
        : annotationsData;
      currentDiffInstance.setLineAnnotations(annotations);
      currentDiffInstance.rerender();
    } catch (error) {
      console.error('Error setting annotations:', error);
      postToSwift('error', { message: error.message });
    }
  },

  /**
   * Removes all line annotations
   */
  removeAnnotations() {
    if (!currentDiffInstance) return;
    currentDiffInstance.setLineAnnotations([]);
    currentDiffInstance.rerender();
  },

  /**
   * Cleans up the current diff instance
   */
  cleanup() {
    if (currentDiffInstance) {
      currentDiffInstance.cleanUp();
      currentDiffInstance = null;
    }
    const container = getContainer();
    container.innerHTML = '';
  },
};

// Also expose raw utilities for advanced usage
window.PierreDiffs = {
  FileDiff,
  parseDiffFromFile,
};

// Signal that the bridge is ready
document.addEventListener('DOMContentLoaded', () => {
  postToSwift('bridgeReady');
});

// Handle system theme changes
window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', (e) => {
  postToSwift('systemThemeChanged', { isDark: e.matches });
});


// Apply touch-only affordances as soon as Pierre attaches its DOM.
(function() {
  const tick = () => {
    applyTouchAffordances(document);
  };
  tick();
  const mo = new MutationObserver(tick);
  mo.observe(document.body || document.documentElement, { childList: true, subtree: true });
})();
