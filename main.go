package main

import (
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/urth-inc/vrm-transform/pkg/glb"
)

const (
	defaultPort        = "4000"
	formFieldFile      = "file"
	maxRequestBodySize = 100 << 20 // 100 MiB
)

const indexHTML = `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>VRM / GLB Transform</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    body {
      font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      margin: 0;
      padding: 24px;
      background: #0f172a;
      color: #e5e7eb;
    }
    .container {
      max-width: 640px;
      margin: 0 auto;
      background: #020617;
      border-radius: 12px;
      padding: 24px 24px 20px;
      box-shadow: 0 18px 45px rgba(15, 23, 42, 0.8);
      border: 1px solid rgba(148, 163, 184, 0.25);
    }
    h1 {
      font-size: 24px;
      margin: 0 0 8px;
      letter-spacing: 0.02em;
    }
    p {
      margin: 0 0 16px;
      font-size: 14px;
      color: #9ca3af;
    }
    label {
      display: block;
      font-size: 13px;
      font-weight: 500;
      margin-bottom: 6px;
      color: #e5e7eb;
    }
    input[type="file"],
    input[type="number"] {
      width: 100%;
      box-sizing: border-box;
      padding: 8px 10px;
      border-radius: 8px;
      border: 1px solid #4b5563;
      background: #020617;
      color: #e5e7eb;
      font-size: 13px;
    }
    input[type="number"] {
      -moz-appearance: textfield;
    }
    input[type="number"]::-webkit-outer-spin-button,
    input[type="number"]::-webkit-inner-spin-button {
      -webkit-appearance: none;
      margin: 0;
    }
    .row {
      display: flex;
      gap: 12px;
    }
    .row > div {
      flex: 1;
    }
    .hint {
      font-size: 12px;
      color: #9ca3af;
      margin-top: 4px;
    }
    button {
      margin-top: 20px;
      display: inline-flex;
      align-items: center;
      gap: 6px;
      padding: 8px 16px;
      border-radius: 999px;
      border: none;
      background: linear-gradient(135deg, #4f46e5, #06b6d4);
      color: white;
      font-size: 14px;
      font-weight: 500;
      cursor: pointer;
      box-shadow: 0 12px 30px rgba(37, 99, 235, 0.45);
    }
    button:hover {
      filter: brightness(1.05);
    }
    button:active {
      transform: translateY(1px);
      box-shadow: 0 6px 18px rgba(37, 99, 235, 0.5);
    }
  </style>
</head>
<body>
  <div class="container">
    <h1>VRM / GLB Transform</h1>
    <p>Upload a VRM/GLB file to convert textures to KTX2. Optionally set atlas resolution.</p>
    <form method="post" action="/transform" enctype="multipart/form-data">
      <div>
        <label for="file">Model file (.glb / .vrm)</label>
        <input id="file" name="file" type="file" required>
      </div>
      <div style="margin-top:16px;">
        <label for="resolution">Square atlas resolution (optional)</label>
        <input id="resolution" name="resolution" type="number" min="1" placeholder="e.g. 1024">
        <div class="hint">If set, width = height = resolution.</div>
      </div>
      <div class="row" style="margin-top:12px;">
        <div>
          <label for="width">Width (optional)</label>
          <input id="width" name="width" type="number" min="1" placeholder="e.g. 2048">
        </div>
        <div>
          <label for="height">Height (optional)</label>
          <input id="height" name="height" type="number" min="1" placeholder="e.g. 1024">
        </div>
      </div>
      <div class="hint">Use either resolution or both width and height. Leave empty to keep size.</div>
      <button type="submit">
        Transform &amp; download
      </button>
    </form>
  </div>
</body>
</html>`

func main() {
	http.HandleFunc("/", handleRoot)
	http.HandleFunc("/transform", handleTransform)
	http.HandleFunc("/health", handleHealth)

	port := defaultPort
	if p := getEnv("PORT", ""); p != "" {
		port = p
	}
	addr := ":" + port
	log.Printf("vrm-transform listening on %s", addr)
	if err := http.ListenAndServe(addr, nil); err != nil {
		log.Fatalf("server failed: %v", err)
	}
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func handleRoot(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", "GET")
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_, _ = io.WriteString(w, indexHTML)
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", "GET")
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_, _ = io.WriteString(w, "ok")
}

func handleTransform(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", "POST")
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	r.Body = http.MaxBytesReader(w, r.Body, maxRequestBodySize)
	if err := r.ParseMultipartForm(maxRequestBodySize); err != nil {
		http.Error(w, "request body too large or invalid multipart", http.StatusBadRequest)
		return
	}

	file, header, err := r.FormFile(formFieldFile)
	if err != nil {
		http.Error(w, "missing or invalid form field: "+formFieldFile, http.StatusBadRequest)
		return
	}
	defer file.Close()

	fileData, err := io.ReadAll(file)
	if err != nil {
		log.Printf("read upload: %v", err)
		http.Error(w, "failed to read uploaded file", http.StatusInternalServerError)
		return
	}

	width, height, err := parseResolution(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	model, err := glb.ReadBinary(fileData)
	if err != nil {
		log.Printf("glb read: %v", err)
		http.Error(w, "invalid GLB/VRM file", http.StatusBadRequest)
		return
	}

	if width > 0 && height > 0 {
		if err := model.ResizeTexture(width, height); err != nil {
			log.Printf("resize texture: %v", err)
			http.Error(w, "texture resize failed", http.StatusInternalServerError)
			return
		}
	}

	deps := &glb.DefaultConvertToKtx2TextureDependencies{}
	if err := model.ToKtx2Texture(deps, "etc1s", 128, -1, -1); err != nil {
		log.Printf("ktx2 convert: %v", err)
		http.Error(w, "KTX2 conversion failed", http.StatusInternalServerError)
		return
	}

	out, err := glb.WriteBinary(model)
	if err != nil {
		log.Printf("glb write: %v", err)
		http.Error(w, "failed to encode output", http.StatusInternalServerError)
		return
	}

	filename := buildOutputFilename(header.Filename)
	w.Header().Set("Content-Type", "application/octet-stream")
	w.Header().Set("Content-Disposition", "attachment; filename=\""+filename+"\"")
	w.WriteHeader(http.StatusOK)
	if _, err := w.Write(out); err != nil {
		log.Printf("write response: %v", err)
	}
}

func parseResolution(r *http.Request) (width, height int, err error) {
	// 表单为 POST multipart，resolution/width/height 在 PostForm 中
	resolution := r.PostFormValue("resolution")
	if resolution != "" {
		n, err := strconv.Atoi(resolution)
		if err != nil || n <= 0 {
			return 0, 0, fmt.Errorf("invalid resolution: must be positive integer")
		}
		return n, n, nil
	}
	wStr := r.PostFormValue("width")
	hStr := r.PostFormValue("height")
	if wStr == "" && hStr == "" {
		return 0, 0, nil
	}
	if wStr != "" && hStr != "" {
		w, e1 := strconv.Atoi(wStr)
		h, e2 := strconv.Atoi(hStr)
		if e1 != nil || e2 != nil || w <= 0 || h <= 0 {
			return 0, 0, fmt.Errorf("invalid width/height: must be positive integers")
		}
		return w, h, nil
	}
	return 0, 0, fmt.Errorf("resolution: use resolution=N or both width and height")
}

func buildOutputFilename(original string) string {
	if original == "" {
		return "output.glb"
	}

	base := filepath.Base(original)
	ext := filepath.Ext(base)
	name := strings.TrimSuffix(base, ext)

	if name == "" {
		if ext == "" {
			return "output.glb"
		}
		return "output_ktx2" + ext
	}

	return name + "_ktx2" + ext
}
