# Retrieval Playground - Workshop Docker Image
# Python 3.12 base image
FROM python:3.12-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    wget \
    gnupg \
    locales \
    openssh-client \
    build-essential \
    make \
    gcc \
    g++ \
    unzip \
    tar \
    zsh \
    tesseract-ocr \
    poppler-utils \
    git \
    curl \
    libgl1 \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# generate the UTF-8 locale so zsh/nvim glyphs and completion behave
RUN sed -i 's/^# *en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && locale-gen

# --- pixi --------------------------------------------------------------------
# Package/env manager (not in apt). Official installer drops the binary in
# $HOME/.pixi/bin; `pixi global install` also exposes tool shims there. Put that
# first on PATH so pixi-provided tools shadow anything from the base image.
ENV PATH=/root/.pixi/bin:$PATH
RUN curl -fsSL https://pixi.sh/install.sh | sh \
    && pixi --version

# --- pixi global tools -------------------------------------------------------
# Every user-facing CLI (from conda-forge). Each package gets its own isolated
# environment; binaries are exposed onto /root/.pixi/bin. Name notes:
#   ripgrep      -> rg
#   fd-find      -> fd
#   git-delta    -> delta
#   tree-sitter-cli -> tree-sitter   (required by nvim-treesitter's `main` branch)
#   nvim         -> neovim itself (the `neovim` package is the python client, not the editor)
#   nodejs       -> node + npm        (mason's JS-based servers)
#   python=3.13  -> python / python3  (mason's Python-based servers)
RUN pixi global install \
      less \
      file \
      git \
      ripgrep \
      fd-find \
      bat \
      jq \
      nodejs \
      luarocks \
      hexyl \
      tree-sitter-cli \
      fzf \
      eza \
      starship \
      git-delta \
      nvim \
      yazi \
      uv

# --- yadm (vendored from upstream, NOT apt) ----------------------------------
# apt's yadm on Ubuntu 24.04 is 3.2.2, whose `alt` stage links with `ln -nfs` and
# thus FORCE-OVERWRITES any pre-existing real file at a symlink target during
# `yadm clone` — silently discarding the user's file (e.g. a hand-written ~/.zshrc).
# The non-destructive behavior ("skip alt if the target already exists", mirroring
# clone's own conflict-protection) landed post-3.5.0 and is not in a tagged release
# yet, so we pin the single-file yadm script at the commit that introduced it.
# yadm is a self-contained bash script; runs after pixi so its deps (git, bash,
# awk) are on PATH. `yadm version` shells out to git, hence the ordering.
ARG YADM_REF=4214de8d91746ca7f7690ebe1fd500c365b3d1b7
RUN curl -fLo /usr/local/bin/yadm \
      "https://github.com/yadm-dev/yadm/raw/${YADM_REF}/yadm" \
    && chmod a+x /usr/local/bin/yadm \
    && yadm version

# --- git version floor -------------------------------------------------------
# The dotfiles' .gitconfig sets `merge.conflictstyle = zdiff3`, which only exists
# in git >= 2.35 (Jan 2022). On older git, *submodule* checkouts abort with
# `fatal: unknown style 'zdiff3'`, silently breaking the only two submodule-bearing
# nvim plugins (luasnip -> deps/jsregexp*, yazi.nvim -> yazi-plugin/yazi-plugins).
# conda-forge's git is well past the floor — this assertion just fails the build
# loudly if that ever regresses.
RUN set -eux; \
    gv="$(git --version | grep -oE '[0-9]+\.[0-9]+' | head -1)"; req=2.35; \
    [ "$(printf '%s\n%s\n' "$req" "$gv" | sort -V | head -1)" = "$req" ] \
      || { echo "FATAL: git $gv < $req — dotfiles need >= $req for zdiff3 (see README)"; exit 1; }; \
    echo "git $gv >= $req OK"

# --- verify expected binary names are on PATH --------------------------------
# Several conda-forge packages expose a binary whose name differs from the package
# (rg, fd, delta, tree-sitter) or bundle a second one (npm). Fail loudly if any
# expected command is missing rather than discovering it at dotfiles-bootstrap time.
RUN set -eux; \
    for c in file git rg fd bat jq python python3 node npm luarocks hexyl \
             tree-sitter fzf eza starship delta nvim yazi zsh yadm; do \
      command -v "$c" >/dev/null || { echo "FATAL: missing command: $c"; exit 1; }; \
    done; \
    echo "all expected commands present"

# --- report what we ended up with -------------------------------------------
RUN echo "=== installed tool versions ===" \
    && for t in file git zsh yadm nvim tree-sitter fzf starship pixi yazi eza bat fd rg jq hexyl delta node npm python luarocks; do \
         printf '%-12s ' "$t"; (command -v "$t" >/dev/null && "$t" --version 2>/dev/null | head -1) || echo "MISSING"; \
       done

# --- personal environment: yadm dotfiles bring-up ----------------------------
# Clone over HTTPS (no build-time SSH secret needed; the repo is public) and let
# `--bootstrap` run .config/yadm/bootstrap, which: links the nvim##default alt,
# runs `nvim --headless "+Lazy! sync" +qa` to install lazy.nvim's plugins, and
# front-loads mason tools + treesitter parsers via provision.lua. See
# gnodar01/dotfiles .config/yadm/bootstrap for the full sequence.
ENV HOME=/root
RUN yadm clone https://github.com/gnodar01/dotfiles.git --bootstrap

# zsh plugins (fzf-tab, zsh-vi-mode, fast-syntax-highlighting) are cloned by
# unplugged.zsh on the first interactive shell, not by the bootstrap (see the
# comment at the top of .config/yadm/bootstrap). Force that first shell now so
# the plugins are baked into the image instead of cloned (with a network
# dependency) the first time someone opens a shell in the running container.
RUN zsh -i -c 'exit'

# Set working directory
WORKDIR /workspace

# Copy the entire project first
COPY . .

# Install Python dependencies
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -e ".[notebook]" && \
    pip install --no-cache-dir "langchain-community>=0.3,<0.4.2" && \
    pip install --no-cache-dir JLDracula


# Pre-download Docling models from HuggingFace (avoids download during workshop)
RUN python -c "\
from docling.document_converter import DocumentConverter; \
from docling.datamodel.pipeline_options import PdfPipelineOptions, TableStructureOptions, TableFormerMode; \
from docling.datamodel.base_models import InputFormat; \
from docling.document_converter import PdfFormatOption; \
print('Pre-downloading Docling models...'); \
pipeline_opts = PdfPipelineOptions( \
    do_table_structure=True, \
    table_structure_options=TableStructureOptions(mode=TableFormerMode.ACCURATE) \
); \
converter = DocumentConverter( \
    format_options={InputFormat.PDF: PdfFormatOption(pipeline_options=pipeline_opts)} \
); \
print('✅ Docling models cached successfully'); \
"

# Create necessary directories
RUN mkdir -p /workspace/retrieval_playground/data/sample_research_papers

# Expose Jupyter port
EXPOSE 8888

# Set environment variables
ENV PYTHONUNBUFFERED=1
ENV JUPYTER_ENABLE_LAB=yes

# Create startup script
RUN echo '#!/bin/bash\n\
echo ""\n\
echo "🧩 Retrieval Playground - Workshop Environment"\n\
echo "============================================"\n\
echo ""\n\
if [ ! -f .env ]; then\n\
    echo "⚠️  WARNING: .env file not found!"\n\
    echo "Please create a .env file with your API keys."\n\
    echo "See .env.example for the required format."\n\
    echo ""\n\
fi\n\
echo "Starting Jupyter Notebook..."\n\
echo ""\n\
echo "📝 Once started, you will see a URL like:"\n\
echo "   http://127.0.0.1:8888/tree?token=..."\n\
echo ""\n\
echo "Copy and paste that URL into your browser."\n\
echo ""\n\
echo "============================================"\n\
echo ""\n\
python -m jupyter notebook --ip=0.0.0.0 --port=8888 --no-browser --allow-root --NotebookApp.token="" --NotebookApp.password=""\n\
' > /workspace/start.sh && chmod +x /workspace/start.sh

# Default command
CMD ["/workspace/start.sh"]
