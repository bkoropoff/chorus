project = "Chorus"
author = "Brian Koropoff"
copyright = "2025 Brian Koropoff"
version = "0.1.0"

extensions = [
    "sphinx_lua_ls",
    "myst_parser"
]

html_theme = "sphinx_rtd_theme"
lua_ls_project_root = "../lua"
lua_ls_backend = "emmylua"
lua_ls_apidoc_format = "md"

lua_ls_default_options = {
    'members': "",
    'globals': "",
    'recursive': "",
    'inherited-members': "",    # Include inherited members
    'module-member-order': "groupwise"  # Sort members by name
}
