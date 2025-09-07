VIMRUNTIME := `nvim --clean --headless -c 'echo $VIMRUNTIME | q' 2>&1`
HTML_OUT := "html-out"

default: doc

# clean outputs
clean:
    rm -rf {{HTML_OUT}}

# build HTML docs
doc:
    rm -rf {{HTML_OUT}}
    env VIMRUNTIME={{VIMRUNTIME}} sphinx-build -v doc {{HTML_OUT}}

serve:
    python -m http.server -b 127.0.0.1 -d {{HTML_OUT}} 8080
