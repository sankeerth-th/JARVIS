#!/bin/zsh
set -euo pipefail

pattern='SourcePackages/checkouts/LocalLLMClient/Sources/LocalLLMClientLlama/Model.swift'
files=("$HOME"/Library/Developer/Xcode/DerivedData/Jarvis-*/$pattern)

if (( ${#files[@]} == 0 )); then
  echo "No LocalLLMClient Model.swift checkout found under DerivedData." >&2
  exit 1
fi

for file in $files; do
  [[ -f "$file" ]] || continue
  chmod u+w "$file"
  python3 - "$file" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
old = '''        model_params.use_mmap = true

        guard let model = llama_model_load_from_file(url.path(), model_params) else {
            throw .failedToLoad(reason: "Failed to load model from file")
        }

        self.model = model

        let chatTemplate = getString(capacity: 8192) { buffer, length in
            // LLM_KV_TOKENIZER_CHAT_TEMPLATE
            llama_model_meta_val_str(model, "tokenizer.chat_template", buffer, length)
        }
'''
new = '''        model_params.use_mmap = true

        let loadedModel: OpaquePointer
        if let model = llama_model_load_from_file(url.path(), model_params) {
            loadedModel = model
        } else {
            model_params.use_mmap = false
            guard let fallbackModel = llama_model_load_from_file(url.path(), model_params) else {
                throw .failedToLoad(reason: "Failed to load model from file")
            }
            loadedModel = fallbackModel
        }

        self.model = loadedModel

        let chatTemplate = getString(capacity: 8192) { buffer, length in
            // LLM_KV_TOKENIZER_CHAT_TEMPLATE
            llama_model_meta_val_str(loadedModel, "tokenizer.chat_template", buffer, length)
        }
'''
if new in text:
    print(f"already patched: {path}")
elif old in text:
    path.write_text(text.replace(old, new, 1))
    print(f"patched: {path}")
else:
    raise SystemExit(f"expected pattern not found in {path}")
PY
done
