(function (global) {
  "use strict";
  const provenance = Object.freeze({
    qualification: "candidate-unqualified",
    renderer: "browser-canvas-foreignObject",
    canonicalCapture: false,
    reason: "Only an actual in-app Browser WindowServer capture can become canonical."
  });

  async function exportCandidatePNG(element, options) {
    if (!element) throw new TypeError("export target is required");
    const opts = options || {};
    const rect = element.getBoundingClientRect();
    const scale = Number.isFinite(opts.scale) ? opts.scale : 2;
    const clone = element.cloneNode(true);
    const serialized = new XMLSerializer().serializeToString(clone);
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${rect.width}" height="${rect.height}"><foreignObject width="100%" height="100%"><div xmlns="http://www.w3.org/1999/xhtml">${serialized}</div></foreignObject></svg>`;
    const image = new Image();
    const url = URL.createObjectURL(new Blob([svg], { type: "image/svg+xml;charset=utf-8" }));
    try {
      await new Promise((resolve, reject) => { image.onload = resolve; image.onerror = () => reject(new Error("candidate SVG rasterization failed")); image.src = url; });
      const canvas = document.createElement("canvas");
      canvas.width = Math.max(1, Math.ceil(rect.width * scale));
      canvas.height = Math.max(1, Math.ceil(rect.height * scale));
      const context = canvas.getContext("2d");
      context.scale(scale, scale);
      context.drawImage(image, 0, 0);
      const blob = await new Promise(resolve => canvas.toBlob(resolve, "image/png"));
      if (!blob || blob.type !== "image/png") throw new Error("candidate export did not produce PNG bytes");
      const bytes = new Uint8Array(await blob.arrayBuffer());
      if (!(bytes[0] === 137 && bytes[1] === 80 && bytes[2] === 78 && bytes[3] === 71)) throw new Error("invalid PNG signature");
      if (opts.download) {
        const anchor = document.createElement("a");
        anchor.download = opts.filename || "halo-reference-candidate-unqualified.png";
        anchor.href = URL.createObjectURL(blob);
        anchor.click();
      }
      return { blob, bytes, width: canvas.width, height: canvas.height, provenance };
    } finally {
      URL.revokeObjectURL(url);
    }
  }
  global.HaloReferenceExport = { exportCandidatePNG, provenance };
})(window);
