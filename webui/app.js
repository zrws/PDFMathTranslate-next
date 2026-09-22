/* ==========================================================================
   PDFMathTranslate-next · Web UI 前端
   - ui 组件层：Toast 提示 / 对话框（替代原生 alert、confirm，保持桌面应用观感）
   - 页面切换与侧边栏高亮
   - 后端 REST API 对接：设置读写、文件上传、任务提交/进度/下载、术语表
   ========================================================================== */

(function () {
  "use strict";

  var DEFAULT_PAGE = "home";
  var POLL_INTERVAL = 1500;
  var PREVIEW_PLACEHOLDER = "预览渲染接入中";

  /* ------------------------------------------------------------ DOM 工具 */
  function $(id) { return document.getElementById(id); }
  function setText(el, text) { if (el) el.textContent = text == null ? "" : String(text); }
  function show(el, visible) { if (el) el.style.display = visible ? "" : "none"; }
  function esc(text) {
    return String(text == null ? "" : text).replace(/[&<>"']/g, function (ch) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[ch];
    });
  }
  function icon(id, cls) {
    return '<svg class="icon' + (cls ? " " + cls : "") + '"><use href="#' + id + '"/></svg>';
  }

  /* ============================================================ ui 组件层 */
  var ui = (function () {
    var stack = null;

    function stackNode() {
      if (!stack) {
        stack = document.createElement("div");
        stack.className = "toast-stack";
        document.body.appendChild(stack);
      }
      return stack;
    }

    var ICONS = {
      success: "i-circle-check",
      error: "i-triangle-alert",
      info: "i-info",
      loading: "i-loader",
    };

    function toast(options) {
      var opts = options || {};
      var type = opts.type || "info";
      var node = document.createElement("div");
      node.className = "toast";
      if (type === "loading") node.style.position = "relative";
      node.innerHTML =
        '<span class="toast-icon ' + type + '">' + icon(ICONS[type] || ICONS.info) + "</span>" +
        '<span class="toast-texts">' +
        '  <span class="toast-title">' + esc(opts.title || "") + "</span>" +
        (opts.desc ? '<span class="toast-desc">' + esc(opts.desc) + "</span>" : "") +
        "</span>" +
        '<button class="toast-close" title="关闭">' + icon("i-x") + "</button>" +
        (type === "loading" ? '<span class="toast-progress"></span>' : "");
      stackNode().appendChild(node);

      var closed = false;
      function close() {
        if (closed) return;
        closed = true;
        node.classList.add("leaving");
        setTimeout(function () { if (node.parentNode) node.parentNode.removeChild(node); }, 180);
      }

      node.querySelector(".toast-close").addEventListener("click", close);
      var timer = null;
      if (type !== "loading" && opts.duration !== 0) {
        timer = setTimeout(close, opts.duration || 3200);
      }

      return {
        close: function () { if (timer) clearTimeout(timer); close(); },
        update: function (title, desc) {
          setText(node.querySelector(".toast-title"), title);
          var descNode = node.querySelector(".toast-desc");
          if (descNode) setText(descNode, desc);
        },
      };
    }

    /**
     * 对话框。options: { title, desc, confirmText, cancelText, destructive, narrow, loading }
     * 返回 Promise<boolean>（确认 true / 取消 false）
     */
    function dialog(options) {
      var opts = options || {};
      return new Promise(function (resolve) {
        var overlay = document.createElement("div");
        overlay.className = "overlay";
        var cancelHtml = opts.cancelText === null
          ? ""
          : '<button class="btn btn-outline" data-role="cancel">' + esc(opts.cancelText || "取消") + "</button>";
        var iconHtml = opts.loading
          ? '<span class="dialog-icon-wrap"><span class="spinner"></span></span>'
          : "";
        overlay.innerHTML =
          '<div class="dialog' + (opts.narrow || opts.loading ? " narrow" : "") + '" role="dialog" aria-modal="true">' +
          iconHtml +
          (opts.title ? '<h2 class="dialog-title">' + esc(opts.title) + "</h2>" : "") +
          (opts.desc ? '<p class="dialog-desc">' + esc(opts.desc) + "</p>" : "") +
          '<div class="dialog-actions">' + cancelHtml +
          '<button class="btn ' + (opts.destructive ? "btn-destructive" : "btn-primary") + '" data-role="confirm">' +
          esc(opts.confirmText || "确定") + "</button>" +
          "</div></div>";

        function finish(result) {
          document.removeEventListener("keydown", onKey, true);
          if (overlay.parentNode) overlay.parentNode.removeChild(overlay);
          resolve(result);
        }

        function onKey(event) {
          if (event.key === "Escape") { event.preventDefault(); finish(false); }
          else if (event.key === "Enter") { event.preventDefault(); finish(true); }
        }

        overlay.addEventListener("click", function (event) {
          if (event.target === overlay && opts.dismissable !== false) finish(false);
        });
        var confirmBtn = overlay.querySelector('[data-role="confirm"]');
        confirmBtn.addEventListener("click", function () { finish(true); });
        var cancelBtn = overlay.querySelector('[data-role="cancel"]');
        if (cancelBtn) cancelBtn.addEventListener("click", function () { finish(false); });

        document.addEventListener("keydown", onKey, true);
        document.body.appendChild(overlay);
        confirmBtn.focus();
      });
    }

    return {
      toast: toast,
      dialog: dialog,
      success: function (title, desc) { return toast({ type: "success", title: title, desc: desc }); },
      error: function (title, desc) { return toast({ type: "error", title: title, desc: desc, duration: 5200 }); },
      info: function (title, desc) { return toast({ type: "info", title: title, desc: desc }); },
      loading: function (title, desc) { return toast({ type: "loading", title: title, desc: desc, duration: 0 }); },
      alert: function (title, desc) {
        return dialog({ title: title, desc: desc, confirmText: "知道了", cancelText: null, narrow: true });
      },
      confirm: function (options) {
        var opts = options || {};
        return dialog({
          title: opts.title,
          desc: opts.desc,
          confirmText: opts.confirmText || "确定",
          cancelText: opts.cancelText || "取消",
          destructive: !!opts.destructive,
        });
      },
    };
  })();

  /* ------------------------------------------------------------------ API */
  function api(path, options) {
    return fetch(path, options).then(function (res) {
      var type = res.headers.get("content-type") || "";
      var parse = type.indexOf("application/json") >= 0 ? res.json() : res.text();
      return parse.then(function (body) {
        if (!res.ok) {
          var detail = body && body.detail ? body.detail : res.status + " " + res.statusText;
          throw new Error(detail);
        }
        return body;
      });
    });
  }
  function postJson(path, payload) {
    return api(path, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(payload || {}) });
  }
  function putJson(path, payload) {
    return api(path, { method: "PUT", headers: { "Content-Type": "application/json" }, body: JSON.stringify(payload || {}) });
  }

  /* ---------------------------------------------------------------- 状态 */
  var state = {
    file: null,
    task: null,
    pollTimer: null,
    settings: null,
    submitting: false,
    prefs: {},
    preview: { source: null, page: 1, pages: 1 },
  };

  /* ------------------------------------------------------------- 格式化 */
  function fmtSize(bytes) {
    if (!bytes) return "";
    if (bytes < 1024) return bytes + " B";
    if (bytes < 1048576) return (bytes / 1024).toFixed(0) + " KB";
    return (bytes / 1048576).toFixed(1) + " MB";
  }
  function fmtDuration(seconds) {
    if (seconds == null) return "";
    if (seconds < 60) return Math.round(seconds) + " 秒";
    return Math.floor(seconds / 60) + " 分 " + Math.round(seconds % 60) + " 秒";
  }
  function fmtTime(ts) {
    if (!ts) return "";
    var date = new Date(ts * 1000);
    var now = new Date();
    var hhmm = ("0" + date.getHours()).slice(-2) + ":" + ("0" + date.getMinutes()).slice(-2);
    if (date.toDateString() === now.toDateString()) return "今天 " + hhmm;
    var yesterday = new Date(now.getTime() - 86400000);
    if (date.toDateString() === yesterday.toDateString()) return "昨天 " + hhmm;
    return (date.getMonth() + 1) + "-" + date.getDate() + " " + hhmm;
  }

  function statusLabel(status) {
    return { running: "翻译中", queued: "排队中", done: "已完成", failed: "失败", cancelled: "已取消" }[status] || status;
  }
  function statusDotClass(status) {
    if (status === "running") return "running";
    if (status === "done") return "done";
    if (status === "failed") return "failed";
    return "queued";
  }
  /** 页数 / 页范围统一展示，避免把 "1-5" 当成页数 */
  function pagesLabel(task) {
    if (task.page_count) return task.page_count + " 页";
    if (task.pages) return "页范围 " + task.pages;
    return "";
  }
  function taskStatusText(task) {
    if (task.status === "done") {
      var parts = [pagesLabel(task), task.duration != null ? "用时 " + fmtDuration(task.duration) : ""].filter(Boolean);
      return "已完成" + (parts.length ? " · " + parts.join(" · ") : "");
    }
    if (task.status === "failed") return "失败 · " + (task.error || "未知错误");
    if (task.status === "cancelled") return "已取消";
    return (task.message || statusLabel(task.status)) + " · " + Math.round(task.progress || 0) + "%";
  }

  /* ------------------------------------------------------------ 页面切换 */
  var navItems = Array.prototype.slice.call(document.querySelectorAll(".nav-item[data-page]"));
  var pages = Array.prototype.slice.call(document.querySelectorAll(".page"));

  function showPage(pageId) {
    var target = pages.some(function (p) { return p.id === "page-" + pageId; }) ? pageId : DEFAULT_PAGE;
    pages.forEach(function (page) { page.classList.toggle("active", page.id === "page-" + target); });
    navItems.forEach(function (item) { item.classList.toggle("active", item.dataset.page === target); });
    if (window.history && window.history.replaceState) {
      window.history.replaceState(null, "", "#" + target);
    }
  }
  navItems.forEach(function (item) {
    item.addEventListener("click", function () { showPage(item.dataset.page); });
  });

  /* ------------------------------------------------------------ 开关辅助 */
  function switchRowInput(labelPrefix) {
    var rows = Array.prototype.slice.call(document.querySelectorAll(".switch-row"));
    for (var i = 0; i < rows.length; i++) {
      var label = rows[i].querySelector(".switch-label");
      if (label && label.textContent.trim().indexOf(labelPrefix) === 0) {
        return rows[i].querySelector('input[type="checkbox"]');
      }
    }
    return null;
  }
  function switchChecked(labelPrefix, fallback) {
    var input = switchRowInput(labelPrefix);
    return input ? input.checked : !!fallback;
  }

  /* --------------------------------------------------------------- 下载 */
  function triggerDownload(url) {
    var link = document.createElement("a");
    link.href = url;
    link.download = "";
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  }

  /* --------------------------------------------------------------- 首页 */
  function initHome() {
    var dropzone = $("dropzone");
    var picker = document.createElement("input");
    picker.type = "file";
    picker.accept = "application/pdf,.pdf";
    picker.style.display = "none";
    document.body.appendChild(picker);

    if (dropzone) {
      dropzone.addEventListener("click", function () { picker.click(); });
      ["dragenter", "dragover"].forEach(function (name) {
        dropzone.addEventListener(name, function (event) {
          event.preventDefault();
          dropzone.style.borderColor = "var(--primary)";
        });
      });
      ["dragleave", "drop"].forEach(function (name) {
        dropzone.addEventListener(name, function (event) {
          event.preventDefault();
          dropzone.style.borderColor = "";
        });
      });
      dropzone.addEventListener("drop", function (event) {
        var file = event.dataTransfer && event.dataTransfer.files[0];
        if (file) uploadFile(file);
      });
    }

    picker.addEventListener("change", function () {
      if (picker.files && picker.files[0]) uploadFile(picker.files[0]);
      picker.value = "";
    });

    var translateBtn = $("translate-btn");
    if (translateBtn) translateBtn.addEventListener("click", startTranslate);
    var cancelBtn = $("cancel-btn");
    if (cancelBtn) cancelBtn.addEventListener("click", cancelTask);
    var dual = $("dl-dual");
    if (dual) dual.addEventListener("click", function () { downloadOutput("dual"); });
    var mono = $("dl-mono");
    if (mono) mono.addEventListener("click", function () { downloadOutput("mono"); });
    var historyBtn = $("home-history-btn");
    if (historyBtn) historyBtn.addEventListener("click", function () { showPage("queue"); });

    initPreviewNav();

    var removeFile = $("file-remove");
    if (removeFile) {
      removeFile.addEventListener("click", function () {
        state.file = null;
        show($("file-row"), false);
        state.preview = { source: null, page: 1, pages: 1 };
        setText($("preview-badge"), "未选择文件");
        var area = $("preview-area");
        if (area) area.textContent = "PDF 预览";
        ui.info("已移除文件", "可以重新选择一份 PDF");
      });
    }

    // 页码范围：仅「自定义页码」时显示输入框
    var rangeSelect = $("pagerange");
    var customField = $("customrange") ? $("customrange").closest(".field") : null;
    function syncRangeField() {
      if (!customField || !rangeSelect) return;
      var custom = rangeSelect.value.indexOf("自定义") === 0;
      customField.style.visibility = custom ? "" : "hidden";
    }
    if (rangeSelect) {
      rangeSelect.addEventListener("change", syncRangeField);
      syncRangeField();
    }

    show($("dl-dual"), false);
    show($("dl-mono"), false);
  }

  function uploadFile(file) {
    if (!/\.pdf$/i.test(file.name)) { ui.error("文件格式不支持", "仅支持 PDF 文件"); return; }
    var dropzone = $("dropzone");
    var text = dropzone ? dropzone.querySelector(".dropzone-text") : null;
    var original = text ? text.textContent : "";
    if (text) text.textContent = "正在上传 " + file.name + " …";
    var pending = ui.loading("正在上传 " + file.name, "解析文档信息…");

    var form = new FormData();
    form.append("file", file);
    api("/api/files", { method: "POST", body: form })
      .then(function (info) {
        pending.close();
        state.file = info;
        renderFileRow(info);
        renderPreview(info);
        ui.success("文件已就绪", info.filename + (info.pages ? "（" + info.pages + " 页）" : ""));
        if (text) text.textContent = original;
      })
      .catch(function (error) {
        pending.close();
        if (text) text.textContent = original;
        ui.error("上传失败", error.message);
      });
  }

  function renderFileRow(info) {
    var row = $("file-row");
    if (!row) return;
    var meta = row.querySelector(".file-meta");
    if (meta) {
      setText(meta.querySelector(".file-name"), info.filename);
      var bits = [];
      if (info.pages) bits.push(info.pages + " 页");
      if (info.size) bits.push(fmtSize(info.size));
      setText(meta.querySelector(".file-info"), bits.join(" · ") || "已上传");
    }
    setText(row.querySelector(".chip"), "已就绪");
    show(row, true);
  }

  function renderPreview(info) {
    setPreviewSource("/api/files/" + encodeURIComponent(info.file_id) + "/preview", info.pages || 1);
  }

  function resolvePages() {
    var select = $("pagerange");
    var value = select ? select.value : "";
    if (value.indexOf("前 5") === 0) return "1-5";
    if (value.indexOf("自定义") === 0) {
      var custom = $("customrange");
      return custom && custom.value.trim() ? custom.value.trim() : null;
    }
    return null;
  }

  function startTranslate() {
    if (state.submitting) return;
    if (!state.file) { ui.alert("还没有选择文件", "请先拖拽或点击上传一份 PDF 文档。"); return; }

    var payload = {
      file_id: state.file.file_id,
      lang_in: $("langfrom") ? $("langfrom").value : null,
      lang_out: $("langto") ? $("langto").value : null,
      pages: resolvePages(),
      no_dual: !switchChecked("双语对照输出", true),
      no_mono: !switchChecked("单语纯净输出", true),
      auto_term_extraction: switchChecked("自动术语提取", false),
    };
    if (payload.no_dual && payload.no_mono) {
      ui.alert("输出模式不能同时关闭", "「双语对照输出」与「单语纯净输出」至少开启一项。");
      return;
    }

    state.submitting = true;
    postJson("/api/tasks", payload)
      .then(function (task) {
        state.task = task;
        renderProgress(task);
        startPolling();
        refreshQueue();
        ui.info("已开始翻译", "任务已加入队列，可在任务队列查看进度");
      })
      .catch(function (error) { ui.error("提交失败", error.message); })
      .then(function () { state.submitting = false; });
  }

  function startPolling() {
    if (state.pollTimer) clearInterval(state.pollTimer);
    state.pollTimer = setInterval(pollTask, POLL_INTERVAL);
    pollTask();
  }

  function pollTask() {
    if (!state.task) return;
    api("/api/tasks/" + state.task.id)
      .then(function (task) {
        state.task = task;
        renderProgress(task);
        if (task.status === "done" || task.status === "failed" || task.status === "cancelled") {
          if (state.pollTimer) { clearInterval(state.pollTimer); state.pollTimer = null; }
          refreshQueue();
          refreshHistory();
          refreshOutputs();
          if (task.status === "done") {
            var previewKind = task.outputs && task.outputs.dual
              ? "dual"
              : (task.outputs && task.outputs.mono ? "mono" : null);
            if (previewKind) {
              setPreviewSource("/api/tasks/" + task.id + "/preview?kind=" + previewKind, task.page_count || 1);
            }
            ui.success("翻译完成", "双语 / 单语 PDF 已生成，可在文档输出中下载");
            if (switchChecked("翻译完成后打开输出目录", false) && task.outputs) {
              revealOutput(task);
            }
          } else if (task.status === "failed") {
            ui.error("翻译失败", task.error || "未知错误");
          } else {
            ui.info("已取消", "任务已停止");
          }
        }
      })
      .catch(function () { /* 轮询失败静默重试 */ });
  }

  function renderProgress(task) {
    setText($("progress-desc"), task.status === "running" ? "任务进行中" : statusLabel(task.status));
    setText($("progress-status"), task.message || statusLabel(task.status));
    var percent = Math.round(task.progress || 0);
    setText($("progress-percent"), percent + "%");
    var fill = $("progress-fill");
    if (fill) fill.style.width = percent + "%";
    var outputs = task.outputs || {};
    show($("dl-dual"), task.status === "done" && !!outputs.dual);
    show($("dl-mono"), task.status === "done" && !!outputs.mono);
  }

  function cancelTask() {
    if (!state.task) { ui.alert("没有进行中的任务", "请先提交一次翻译。"); return; }
    if (state.task.status !== "running" && state.task.status !== "queued") {
      ui.alert("任务已结束", "当前任务状态：" + statusLabel(state.task.status));
      return;
    }
    ui.confirm({
      title: "取消当前翻译？",
      desc: "已完成的页面不会保留，稍后需要重新开始。",
      confirmText: "取消任务",
      cancelText: "继续翻译",
      destructive: true,
    }).then(function (ok) {
      if (!ok) return;
      postJson("/api/tasks/" + state.task.id + "/cancel", {})
        .then(function (task) { state.task = task; renderProgress(task); })
        .catch(function (error) { ui.error("取消失败", error.message); });
    });
  }

  function downloadOutput(kind) {
    if (!state.task || !state.task.outputs || !state.task.outputs[kind]) {
      ui.alert("暂无可下载文件", "翻译完成后才能下载。");
      return;
    }
    triggerDownload("/api/tasks/" + state.task.id + "/download?kind=" + kind);
  }

  function revealOutput(task) {
    var path = task.outputs && (task.outputs.dual || task.outputs.mono);
    if (!path) return;
    postJson("/api/reveal", { path: path }).catch(function () { /* 忽略 */ });
  }

  /* --------------------------------------------------------- PDF 预览 */
  function setPreviewSource(source, fallbackPages) {
    state.preview = { source: source, page: 1, pages: fallbackPages || 1 };
    var probe = source + (source.indexOf("?") >= 0 ? "&" : "?") + "page=1&width=400";
    fetch(probe)
      .then(function (res) {
        var count = parseInt(res.headers.get("X-Page-Count") || "", 10);
        if (!isNaN(count) && count > 0) state.preview.pages = count;
      })
      .catch(function () { })
      .then(function () { loadPreview(1); });
  }

  function loadPreview(page) {
    var area = $("preview-area");
    if (!area || !state.preview.source) return;
    var total = state.preview.pages || 1;
    var target = Math.max(1, Math.min(page, total));
    state.preview.page = target;
    var url = state.preview.source + (state.preview.source.indexOf("?") >= 0 ? "&" : "?") + "page=" + target + "&width=900";
    area.innerHTML = "<img class=\"preview-image\" alt=\"第 " + target + " 页\" src=\"" + url + "\">";
    setText($("preview-badge"), "第 " + target + " / " + total + " 页");
    var prev = $("preview-prev");
    var next = $("preview-next");
    if (prev) prev.disabled = target <= 1;
    if (next) next.disabled = target >= total;
  }

  function initPreviewNav() {
    var prev = $("preview-prev");
    var next = $("preview-next");
    if (prev) prev.addEventListener("click", function () { loadPreview(state.preview.page - 1); });
    if (next) next.addEventListener("click", function () { loadPreview(state.preview.page + 1); });
  }

  /* ------------------------------------------------------- 偏好与主题 */
  function applyTheme(mode) {
    var resolved = mode === "system"
      ? (window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light")
      : mode;
    document.documentElement.dataset.theme = resolved;
    var button = $("topbar-theme");
    if (button) {
      button.innerHTML = icon(resolved === "dark" ? "i-moon" : "i-sun");
      button.title = resolved === "dark" ? "切换到浅色主题" : "切换到深色主题";
    }
  }

  function themeFromLabel(label) {
    if (label === "深色") return "dark";
    if (label === "浅色") return "light";
    return "system";
  }

  function loadPrefs() {
    return api("/api/prefs").then(function (prefs) {
      state.prefs = prefs || {};
      applyTheme(state.prefs.theme || "system");
      var autoUpdate = switchRowInput("启动时自动检查更新");
      if (autoUpdate) autoUpdate.checked = state.prefs.auto_update !== false;
      var openOutput = switchRowInput("翻译完成后打开输出目录");
      if (openOutput) openOutput.checked = state.prefs.open_output_dir === true;
      var themeSelect = $("theme");
      if (themeSelect) {
        themeSelect.value = state.prefs.theme === "dark" ? "深色" : (state.prefs.theme === "light" ? "浅色" : "跟随系统");
      }
    }).catch(function () { applyTheme("system"); });
  }

  function savePrefs(patch) {
    state.prefs = Object.assign({}, state.prefs, patch);
    return putJson("/api/prefs", patch).catch(function () { });
  }

  function initTopbar() {
    var github = $("topbar-github");
    if (github) {
      github.addEventListener("click", function () {
        window.open("https://github.com/zrws/PDFMathTranslate-next", "_blank");
      });
    }
    var theme = $("topbar-theme");
    if (theme) {
      theme.addEventListener("click", function () {
        var next = document.documentElement.dataset.theme === "dark" ? "light" : "dark";
        applyTheme(next);
        savePrefs({ theme: next });
        var themeSelect = $("theme");
        if (themeSelect) themeSelect.value = next === "dark" ? "深色" : "浅色";
      });
    }
    var lang = $("topbar-lang");
    if (lang) {
      lang.addEventListener("click", function () {
        var next = state.settings && state.settings.ui_lang === "zh" ? "en" : "zh";
        putJson("/api/settings", { ui_lang: next })
          .then(function () {
            setText($("topbar-lang-text"), next === "zh" ? "简体中文" : "English");
            ui.success("界面语言已保存", "当前为 " + (next === "zh" ? "简体中文" : "English") + "（界面文案本地化将在后续版本提供）");
            return loadSettings();
          })
          .catch(function (error) { ui.error("切换失败", error.message); });
      });
    }
    if (window.matchMedia) {
      window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", function () {
        if ((state.prefs.theme || "system") === "system") applyTheme("system");
      });
    }
  }

  function initThemeSelect() {
    var select = $("theme");
    if (!select) return;
    select.addEventListener("change", function () {
      applyTheme(themeFromLabel(select.value));
      savePrefs({ theme: themeFromLabel(select.value) });
    });
  }

  function initRateMode() {
    var select = $("rate");
    if (!select) return;
    var qpsField = $("qps") ? $("qps").closest(".field") : null;
    var workersField = $("workers") ? $("workers").closest(".field") : null;
    var rateLabel = qpsField ? qpsField.querySelector(".label") : null;
    function sync() {
      var concurrent = select.value.indexOf("并发") === 0;
      if (qpsField) qpsField.style.display = concurrent ? "none" : "";
      if (workersField) workersField.style.display = concurrent ? "" : "none";
      if (rateLabel) rateLabel.textContent = select.value.indexOf("RPM") === 0 ? "RPM" : "QPS";
    }
    select.addEventListener("change", sync);
    sync();
  }

  /* ----------------------------------------------------------- 任务队列 */
  function refreshQueue() {
    return api("/api/tasks").then(function (tasks) {
      var running = tasks.filter(function (t) { return t.status === "running" || t.status === "queued"; }).length;
      setText($("queue-meta"), tasks.length ? "共 " + tasks.length + " 个任务 · " + running + " 个进行中" : "暂无任务");
      var container = $("task-list");
      if (!container) return;
      if (!tasks.length) {
        container.innerHTML = '<p class="hint">还没有翻译任务，去「翻译工作台」上传一份 PDF 试试。</p>';
        return;
      }
      container.innerHTML = tasks.map(function (task) {
        var actions = "";
        if (task.status === "failed") {
          actions += "<button class=\"icon-btn\" title=\"重试\" data-retry=\"" + task.id + "\">" + icon("i-loader") + "</button>";
        }
        if (task.status === "done") {
          if (task.outputs && task.outputs.dual) {
            actions += '<a class="icon-btn" title="下载双语版" href="/api/tasks/' + task.id + '/download?kind=dual" download>' + icon("i-download") + "</a>";
          }
          if (task.outputs && task.outputs.mono) {
            actions += '<a class="icon-btn" title="下载单语版" href="/api/tasks/' + task.id + '/download?kind=mono" download>' + icon("i-download") + "</a>";
          }
          actions += '<button class="icon-btn" title="打开输出目录" data-reveal="' + task.id + '">' + icon("i-folder-open") + "</button>";
        }
        return '<div class="task-row">' +
          '<div class="task-info">' +
          '<span class="dot ' + statusDotClass(task.status) + '"></span>' +
          '<span class="task-text">' +
          '<span class="task-name">' + esc(task.filename) + "</span>" +
          '<span class="task-status">' + esc(taskStatusText(task)) + "</span>" +
          "</span></div>" +
          '<div class="task-actions">' + actions + "</div></div>";
      }).join("");

      Array.prototype.slice.call(container.querySelectorAll("button[data-reveal]")).forEach(function (button) {
        button.addEventListener("click", function () {
          var task = tasks.filter(function (t) { return t.id === button.dataset.reveal; })[0];
          if (task) revealOutput(task);
        });
      });

      Array.prototype.slice.call(container.querySelectorAll("button[data-retry]")).forEach(function (button) {
        button.addEventListener("click", function () {
          postJson("/api/tasks/" + button.dataset.retry + "/retry", {})
            .then(function (task) {
              ui.info("已重新提交", task.filename + " 正在重新翻译");
              state.task = task;
              renderProgress(task);
              startPolling();
              refreshQueue();
            })
            .catch(function (error) { ui.error("重试失败", error.message); });
        });
      });
    }).catch(function () { });
  }

  /* --------------------------------------------------------- 翻译历史 */
  function refreshHistory() {
    return api("/api/tasks").then(function (tasks) {
      var done = tasks.filter(function (t) { return t.status === "done"; });
      setText($("history-desc"), done.length ? "最近完成 · 共 " + done.length + " 个任务" : "最近完成");
      var container = $("history-list");
      if (!container) return;
      if (!done.length) {
        container.innerHTML = '<p class="hint">还没有完成的翻译任务。</p>';
        return;
      }
      container.innerHTML = done.slice(0, 3).map(function (task) {
        var meta = [pagesLabel(task), fmtTime(task.finished_at) + " 完成"].filter(Boolean).join(" · ");
        return '<div class="history-row">' +
          '<span class="task-text">' +
          '<span class="task-name">' + esc(task.filename) + "</span>" +
          '<span class="task-status">' + esc(meta) + "</span>" +
          "</span>" +
          '<span class="chip chip-solid">已完成</span></div>';
      }).join("");
    }).catch(function () { });
  }

  /* --------------------------------------------------------- 文档输出 */
  function refreshOutputs() {
    return api("/api/tasks").then(function (tasks) {
      var done = tasks.filter(function (t) { return t.status === "done"; });
      var container = $("outputs-grid");
      if (!container) return;
      var cards = [];
      done.forEach(function (task) {
        var outputs = task.outputs || {};
        [["dual", "双语对照", "公式保留"], ["mono", "单语纯净", "无水印"]].forEach(function (spec) {
          var kind = spec[0];
          if (!outputs[kind]) return;
          var fileName = outputs[kind].split(/[\\/]/).pop();
          var meta = [pagesLabel(task), fmtTime(task.finished_at)].filter(Boolean).join(" · ");
          cards.push('<article class="file-card">' +
            '<div class="file-top">' +
            '<span class="file-badge">PDF</span>' +
            '<span class="file-meta">' +
            '<span class="file-name">' + esc(fileName) + "</span>" +
            '<span class="file-info">' + esc(meta) + "</span>" +
            "</span></div>" +
            '<div class="chips">' +
            '<span class="chip chip-solid">' + spec[1] + "</span>" +
            '<span class="chip chip-outline">' + spec[2] + "</span>" +
            "</div>" +
            '<div class="file-actions">' +
            '<a class="btn sm btn-secondary" href="/api/tasks/' + task.id + '/download?kind=' + kind + '" download>' + icon("i-download") + "下载</a>" +
            '<button class="icon-btn outline" title="在资源管理器中显示" data-reveal-output="' + task.id + '">' + icon("i-folder-open") + "</button>" +
            "</div></article>");
        });
      });
      container.innerHTML = cards.length ? cards.join("") : '<p class="hint">还没有输出文件，翻译完成后会显示在这里。</p>';

      Array.prototype.slice.call(container.querySelectorAll("button[data-reveal-output]")).forEach(function (button) {
        button.addEventListener("click", function () {
          var task = done.filter(function (t) { return t.id === button.dataset.revealOutput; })[0];
          if (task) revealOutput(task);
        });
      });

      Array.prototype.slice.call(container.querySelectorAll("button[data-retry]")).forEach(function (button) {
        button.addEventListener("click", function () {
          postJson("/api/tasks/" + button.dataset.retry + "/retry", {})
            .then(function (task) {
              ui.info("已重新提交", task.filename + " 正在重新翻译");
              state.task = task;
              renderProgress(task);
              startPolling();
              refreshQueue();
            })
            .catch(function (error) { ui.error("重试失败", error.message); });
        });
      });
    }).catch(function () { });
  }

  function initOutputs() {
    var all = $("download-all");
    if (!all) return;
    all.addEventListener("click", function () {
      api("/api/tasks").then(function (tasks) {
        var urls = [];
        tasks.forEach(function (task) {
          if (task.status !== "done" || !task.outputs) return;
          ["dual", "mono"].forEach(function (kind) {
            if (task.outputs[kind]) urls.push("/api/tasks/" + task.id + "/download?kind=" + kind);
          });
        });
        if (!urls.length) { ui.alert("没有可下载的文件", "完成一次翻译后再试。"); return; }
        urls.forEach(function (url, index) { setTimeout(function () { triggerDownload(url); }, index * 350); });
        ui.success("已开始下载", "共 " + urls.length + " 个文件");
      });
    });
  }

  /* ----------------------------------------------------------- 术语表 */
  function refreshGlossary() {
    return api("/api/glossary").then(function (rows) {
      var container = $("glossary-body");
      if (!container) return;
      var head = '<div class="table-row table-head">' +
        '<span class="table-cell">原文（English）</span>' +
        '<span class="table-cell">译文（简体中文）</span>' +
        '<span class="table-cell action">操作</span></div>';
      if (!rows.length) {
        container.innerHTML = head + '<p class="hint" style="padding:14px 24px">还没有术语，点击「上传术语表」导入 CSV。</p>';
        return;
      }
      container.innerHTML = head + rows.map(function (row) {
        return '<div class="table-row">' +
          '<span class="table-cell">' + esc(row.source) + "</span>" +
          '<span class="table-cell">' + esc(row.target) + "</span>" +
          '<span class="table-cell action">' +
          '<button class="icon-btn" title="删除" data-term="' + esc(row.source) + '" data-file="' + esc(row.file) + '">' + icon("i-trash") + "</button>" +
          "</span></div>";
      }).join("");

      Array.prototype.slice.call(container.querySelectorAll("button[data-term]")).forEach(function (button) {
        button.addEventListener("click", function () {
          ui.confirm({
            title: "删除该术语？",
            desc: button.dataset.term + " 将从术语表中移除。",
            confirmText: "删除",
            destructive: true,
          }).then(function (ok) {
            if (!ok) return;
            api("/api/glossary/" + encodeURIComponent(button.dataset.term) + "?file=" + encodeURIComponent(button.dataset.file), { method: "DELETE" })
              .then(function () { refreshGlossary(); ui.success("已删除术语", button.dataset.term); })
              .catch(function (error) { ui.error("删除失败", error.message); });
          });
        });
      });
    }).catch(function () { });
  }

  function initGlossary() {
    var picker = document.createElement("input");
    picker.type = "file";
    picker.accept = ".csv,.txt";
    picker.style.display = "none";
    document.body.appendChild(picker);
    picker.addEventListener("change", function () {
      if (!picker.files || !picker.files[0]) return;
      var file = picker.files[0];
      var form = new FormData();
      form.append("file", file);
      var pending = ui.loading("正在导入术语表", file.name);
      api("/api/glossary", { method: "POST", body: form })
        .then(function (rows) {
          pending.close();
          refreshGlossary();
          ui.success("术语表已导入", "当前共 " + rows.length + " 条术语");
        })
        .catch(function (error) { pending.close(); ui.error("导入失败", error.message); });
      picker.value = "";
    });
    ["glossary-upload-btn", "glossary-import-btn"].forEach(function (id) {
      var button = $(id);
      if (button) button.addEventListener("click", function () { picker.click(); });
    });
    var downloadBtn = $("glossary-download-btn");
    if (downloadBtn) {
      downloadBtn.addEventListener("click", function () {
        api("/api/tasks").then(function (tasks) {
          var withGlossary = tasks.filter(function (t) { return t.outputs && t.outputs.glossary; })[0];
          if (!withGlossary) {
            ui.alert("暂无自动提取的术语表", "在翻译工作台开启「自动术语提取」后翻译一次即可生成。");
            return;
          }
          triggerDownload("/api/tasks/" + withGlossary.id + "/download?kind=glossary");
        });
      });
    }
  }

  /* ------------------------------------------------------------- 设置 */
  var FONT_OPTIONS = [
    { value: "", label: "跟随默认" },
    { value: "sans-serif", label: "无衬线（思源黑体 / sans-serif）" },
    { value: "serif", label: "衬线（宋体 / serif）" },
    { value: "script", label: "手写体（script）" },
  ];

  function fillOptions(select, options, currentValue) {
    if (!select) return;
    var list = options.slice();
    if (currentValue && !list.some(function (option) { return option.value === currentValue; })) {
      list.unshift({ value: currentValue, label: currentValue });
    }
    select.innerHTML = list.map(function (option) {
      return "<option value=\"" + esc(option.value) + "\"" + (option.value === currentValue ? " selected" : "") + ">" + esc(option.label) + "</option>";
    }).join("");
  }

  function fillSelect(select, values, current) {
    if (!select) return;
    var list = values.slice();
    if (current && list.indexOf(current) < 0) list.unshift(current);
    select.innerHTML = list.map(function (value) {
      return '<option value="' + esc(value) + '"' + (value === current ? " selected" : "") + ">" + esc(value) + "</option>";
    }).join("");
  }

  function loadSettings() {
    return api("/api/settings").then(function (settings) {
      state.settings = settings;
      fillSelect($("svc"), settings.services || [], settings.service);
      if ($("apikey")) {
        $("apikey").value = "";
        $("apikey").placeholder = settings.api_key_set ? settings.api_key_masked + "（留空则不修改）" : "sk-...";
      }
      if ($("baseurl")) $("baseurl").value = settings.base_url || "";
      if ($("model")) $("model").value = settings.model || "";
      if ($("prompt")) $("prompt").value = settings.custom_system_prompt || "";
      if ($("qps")) $("qps").value = settings.qps;
      if ($("workers")) $("workers").value = settings.pool_max_workers == null ? "" : settings.pool_max_workers;
      fillOptions($("font"), FONT_OPTIONS, settings.primary_font_family || "");
      if ($("uilang")) $("uilang").value = settings.ui_lang === "zh" ? "简体中文" : "English";
      var autoUpdate = switchRowInput("启动时自动检查更新");
      if (autoUpdate) autoUpdate.checked = state.prefs.auto_update !== false;
      var openOutput = switchRowInput("翻译完成后打开输出目录");
      if (openOutput) openOutput.checked = state.prefs.open_output_dir === true;
      setText($("topbar-lang-text"), settings.ui_lang === "zh" ? "简体中文" : "English");
    }).catch(function (error) {
      ui.error("无法连接后端", error.message);
    });
  }

  function saveSettings() {
    var payload = {
      service: $("svc") ? $("svc").value : null,
      base_url: $("baseurl") ? $("baseurl").value : null,
      model: $("model") ? $("model").value : null,
      custom_system_prompt: $("prompt") ? $("prompt").value : null,
      primary_font_family: $("font") ? $("font").value : null,
    };
    var key = $("apikey") ? $("apikey").value.trim() : "";
    if (key) payload.api_key = key;
    var uiLangSelect = $("uilang");
    if (uiLangSelect) {
      var langValue = uiLangSelect.value;
      payload.ui_lang = langValue === "English" ? "en" : (langValue === "日本語" ? "ja" : "zh");
    }
    var rateMode = $("rate") ? $("rate").value : "QPS";
    var qpsValue = parseInt($("qps") ? $("qps").value : "", 10);
    var workers = parseInt($("workers") ? $("workers").value : "", 10);
    if (rateMode.indexOf("RPM") === 0) {
      if (!isNaN(qpsValue)) payload.qps = Math.max(1, Math.round(qpsValue / 60));
    } else if (rateMode.indexOf("并发") === 0) {
      if (!isNaN(workers)) payload.pool_max_workers = workers;
    } else if (!isNaN(qpsValue)) {
      payload.qps = qpsValue;
    }

    var autoUpdate = switchRowInput("启动时自动检查更新");
    var openOutput = switchRowInput("翻译完成后打开输出目录");
    savePrefs({
      auto_update: autoUpdate ? autoUpdate.checked : true,
      open_output_dir: openOutput ? openOutput.checked : false,
    });

    var pending = ui.loading("正在保存设置", "写入本机配置文件…");
    return putJson("/api/settings", payload)
      .then(function () {
        pending.close();
        ui.success("设置已保存", "翻译引擎与限流参数已生效");
        return loadSettings();
      })
      .catch(function (error) { pending.close(); ui.error("保存失败", error.message); });
  }

  function initSettings() {
    var save = $("save-settings");
    if (save) save.addEventListener("click", saveSettings);
    var topbar = $("topbar-save");
    if (topbar) topbar.addEventListener("click", saveSettings);
    var reset = $("reset-settings");
    if (reset) {
      reset.addEventListener("click", function () {
        ui.confirm({
          title: "恢复默认设置？",
          desc: "将切换到 SiliconFlow 免费引擎，并清除自定义提示词与已保存的 API Key。",
          confirmText: "恢复默认",
          destructive: true,
        }).then(function (ok) {
          if (!ok) return;
          putJson("/api/settings", { service: "SiliconFlowFree", custom_system_prompt: "", qps: 4 })
            .then(function () { ui.success("已恢复默认设置", "当前使用 SiliconFlow 免费引擎"); return loadSettings(); })
            .catch(function (error) { ui.error("恢复失败", error.message); });
        });
      });
    }
  }

  /* --------------------------------------------------------- 清空记录 */
  function initQueue() {
    var clear = $("clear-history");
    if (!clear) return;
    clear.addEventListener("click", function () {
      api("/api/tasks").then(function (tasks) {
        if (!tasks.length) { ui.alert("暂无记录", "当前没有可清空的任务记录。"); return; }
        ui.confirm({
          title: "清空翻译记录？",
          desc: "将删除全部 " + tasks.length + " 条任务记录（已生成的文件不会被删除）。",
          confirmText: "清空记录",
          destructive: true,
        }).then(function (ok) {
          if (!ok) return;
          api("/api/tasks", { method: "DELETE" })
            .then(function () {
              ui.success("已清空记录", "任务历史已重置");
              refreshQueue();
              refreshHistory();
              refreshOutputs();
            })
            .catch(function (error) { ui.error("清空失败", error.message); });
        });
      });
    });
  }

  /* --------------------------------------------------------------- 启动 */
  function init() {
    initHome();
    initSettings();
    initGlossary();
    initQueue();
    initOutputs();
    initTopbar();
    initThemeSelect();
    initRateMode();
    showPage((window.location.hash || "").replace(/^#/, "") || DEFAULT_PAGE);
    applyTheme("system");
    loadPrefs();
    loadSettings();
    refreshQueue();
    refreshHistory();
    refreshOutputs();
    refreshGlossary();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
